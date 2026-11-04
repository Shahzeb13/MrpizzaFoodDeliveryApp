-- MrPizza: order totals must match the real menu.
--
-- The `orders customer creates own` policy only proves the amounts add up
-- together (subtotal + tax + delivery - discount = total). Nothing stopped an
-- order whose subtotal lied about the food. Sizes, crusts and toppings exist
-- only in the app, so exact totals cannot be recomputed server-side; but
-- extras always stack ON TOP of menu_items.price, which gives an honest
-- floor: no line may be priced below its menu price, and the order subtotal
-- must cover the sum of the raw menu prices.
--
-- This trigger is read-only and rejects (raises) a bad insert. A rejected
-- item insert rolls back its own statement; the order header the app inserted
-- just before stays behind as an unpaid 'confirmed' row for staff to clean
-- up. Nobody can pay for such an order, because payment tokens are only
-- issued against orders whose items passed this gate.
--
-- Rollback if ever needed:
--   DROP TRIGGER trg_menu_floored_order_items ON public.order_items;
--   DROP FUNCTION public.validate_order_menu_pricing();

CREATE OR REPLACE FUNCTION public.validate_order_menu_pricing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $body$
DECLARE
  v_price numeric := NEW.price_at_order;
  v_quantity integer := NEW.quantity;
  v_base_price numeric;
  v_is_available boolean;
  v_subtotal numeric;
  v_items_floor numeric;
BEGIN
  IF v_quantity IS NULL OR v_quantity < 1 THEN
    RAISE EXCEPTION
      'Order line quantity must be at least 1';
  END IF;

  SELECT mi.price, mi.is_available
    INTO v_base_price, v_is_available
    FROM public."menu_items" mi
   WHERE mi.id = NEW.menu_item_id;

  IF v_base_price IS NULL THEN
    RAISE EXCEPTION
      'This menu item no longer exists. Please refresh the menu and try again.';
  END IF;

  IF v_is_available IS NOT TRUE THEN
    RAISE EXCEPTION
      'This menu item is not on sale right now. Please refresh the menu and try again.';
  END IF;

  IF v_price IS NULL OR v_price < v_base_price THEN
    RAISE EXCEPTION
      'Order line price is below the menu price. Please refresh the menu and try again.';
  END IF;

  SELECT o.subtotal
    INTO v_subtotal
    FROM public."orders" o
   WHERE o.id = NEW.order_id;

  IF v_subtotal IS NULL THEN
    RAISE EXCEPTION
      'Order not found for this order item';
  END IF;

  -- AFTER row triggers on this statement run after all rows of the insert are
  -- applied, so this sum already includes the whole cart the app sent.
  SELECT COALESCE(SUM(mi.price * oi.quantity), 0)
    INTO v_items_floor
    FROM public."order_items" oi
    JOIN public."menu_items" mi ON mi.id = oi.menu_item_id
   WHERE oi.order_id = NEW.order_id;

  IF v_subtotal < v_items_floor THEN
    RAISE EXCEPTION
      'Order total does not cover the items ordered. Please refresh the menu and try again.';
  END IF;

  RETURN NEW;
END;
$body$;

-- Read-only validator: reachable only through the trigger, never as a client
-- RPC. PostgREST does not expose trigger-returning functions anyway; the
-- revokes document the intent.
REVOKE EXECUTE ON FUNCTION public.validate_order_menu_pricing() FROM anon;
REVOKE EXECUTE ON FUNCTION public.validate_order_menu_pricing() FROM authenticated;

CREATE TRIGGER trg_menu_floored_order_items
AFTER INSERT ON public.order_items
FOR EACH ROW
EXECUTE FUNCTION public.validate_order_menu_pricing();
