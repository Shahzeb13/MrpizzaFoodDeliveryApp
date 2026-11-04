import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

// Storage keys, all under one prefix so a wipe of "MrPizza's local cache"
// never needs per-feature knowledge.
const localStorageCartKey = 'mrpizza.cart.v1';
const localStorageLocationKey = 'mrpizza.location.v1';
const localStorageOrderTypeKey = 'mrpizza.checkout.orderType.v1';
const localStorageManualBranchIdKey = 'mrpizza.checkout.manualBranchId.v1';

/// App-local key/value storage over `SharedPreferences`.
///
/// Every persist-across-restart feature (cart, delivery address, order type,
/// a hand-picked branch) reads and writes through this one wrapper so they all
/// share the same three promises:
///
/// 1. Storage problems never crash ordering. Reads answer null, writes are
///    swallowed — a broken store means losing a reminder, not losing an order.
/// 2. Nothing waits synchronously. Features capture [ready] once and queue
///    work behind it, so a mutation made the instant the app starts is still
///    eventually written instead of being dropped against a slow first read.
/// 3. One place to change the backing store later.
class LocalStore {
  LocalStore._();

  static final LocalStore instance = LocalStore._();

  SharedPreferences? _prefs;
  Future<SharedPreferences?>? _readyFuture;

  /// Resolves once storage is usable, or to null when it never will be (a unit
  /// test environment without the platform channel, or a device error).
  Future<SharedPreferences?> ready() {
    final existing = _readyFuture;
    if (existing != null) return existing;
    final pending = _open();
    _readyFuture = pending;
    return pending;
  }

  Future<SharedPreferences?> _open() async {
    try {
      return _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return _prefs = null;
    }
  }

  /// Synchronous read, usable once [ready] has resolved. Before that — and
  /// whenever storage is unavailable — null is the honest answer.
  String? readString(String key) {
    final prefs = _prefs;
    if (prefs == null) return null;
    try {
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  /// Writes [value], or removes the key when it is null. Ques behind [ready],
  /// so a value written the moment the app starts is not silently lost.
  Future<void> writeString(String key, String? value) async {
    final prefs = await ready();
    if (prefs == null) return;
    try {
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    } catch (_) {
      // Best-effort by contract: losing a write must not throw past the
      // order flow that triggered it.
    }
  }

  /// Point of no return for tests: the next [ready] opens a fresh store.
  @visibleForTesting
  static void resetForTest() {
    instance._prefs = null;
    instance._readyFuture = null;
  }
}
