/// Serialises work that can be requested from more than one source at once.
///
/// This exists because the order-status stream is driven by two independent
/// triggers: the realtime push and a safety-net poll. They are not alternatives
/// — they are two doors into the same room, and they collide. An event landing
/// a few milliseconds before a tick fires two reads at the same instant, and
/// because nothing orders them, the slower one can resolve LAST with data that
/// was read *before* the change the faster one saw. The customer watches a
/// status advance correctly, rewind, and crawl forward again on the next tick.
///
/// One request at a time removes that rather than papering over it: request N+1
/// cannot begin until request N has finished, so each one necessarily observed
/// the database at least as recently as the one before it.
///
/// The second job is collapsing bursts. Ten realtime events arriving during one
/// slow read mean exactly one follow-up read, not ten — so realtime still
/// shortens the wait instead of being dropped, and a burst cannot be used to
/// hammer the database.
class CoalescedReadGate {
  bool _busy = false;
  bool _closed = false;

  /// The work a trigger that arrived mid-read is owed.
  ///
  /// Held as the actual work, not as a flag. A flag version re-runs the BUSY
  /// caller's closure for the follow-up, which silently substitutes one
  /// trigger's work for another's — harmless when every trigger is the same
  /// "re-read this order" closure, and wrong the moment one is not.
  Future<void> Function()? _queuedWork;

  /// True while a read is running.
  bool get isBusy => _busy;

  /// Whether a trigger is waiting to be served. At most one, by construction.
  bool get hasQueuedRead => _queuedWork != null;

  /// Permanently stops the gate. In-flight work is allowed to finish; anything
  /// it would have queued is dropped.
  void close() => _closed = true;

  /// Runs [read], or schedules exactly one run of it if a read is already going.
  ///
  /// Returns once the gate is idle again for this caller. A caller that arrives
  /// while busy returns before its trigger has been served — the point is that
  /// the read happens, not that the caller waits on it.
  ///
  /// If several triggers arrive during one read, only the LAST is kept. They all
  /// want the same thing — the current state — so running them in order would
  /// spend requests re-deriving an answer the next one supersedes.
  Future<void> request(Future<void> Function() read) async {
    if (_closed) return;
    if (_busy) {
      _queuedWork = read;
      return;
    }

    _busy = true;
    try {
      Future<void> Function()? work = read;
      while (work != null) {
        _queuedWork = null;
        await work();
        // Read whatever arrived while the above was running, unless the gate was
        // closed in the meantime — in which case there is no next read.
        final next = _queuedWork;
        work = (_closed || next == null) ? null : next;
      }
    } finally {
      _busy = false;
      _queuedWork = null;
    }
  }
}