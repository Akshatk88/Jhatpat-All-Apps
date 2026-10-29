package flutter.overlay.window.flutter_overlay_window;

import android.view.WindowManager;

/**
 * Lets the app start flutter_overlay_window's OverlayService natively (from
 * NewOrderReceiver, with no Flutter engine running) with the SAME window the
 * Dart side asks for in OrderOverlayService.showForOrder.
 *
 * The plugin keeps that geometry in WindowSetup's package-private statics, set
 * only by its Dart `showOverlay` call. Started natively in a fresh process they
 * are the plugin defaults instead: full screen, CENTER gravity and not
 * focusable, which put the card in the middle of a screen-sized window (and
 * the Dart overlay's moveOverlay(0, 32) then meant "32dp below the centre").
 * This class lives in the plugin's package only to reach those statics; it
 * mirrors FlutterOverlayWindowPlugin's own "showOverlay" handler (plugin
 * 0.5.0) and must be kept in step with it on a plugin upgrade.
 */
public final class NativeOverlayWindowSetup {
    private NativeOverlayWindowSetup() {}

    /**
     * Same values as `FlutterOverlayWindow.showOverlay(height: …, width:
     * matchParent, alignment: topCenter, flag: focusPointer, enableDrag: false,
     * positionGravity: none, visibility: visibilityPublic)`.
     *
     * @param heightPx initial window height; the overlay resizes it to the
     *     measured card itself (OrderOverlayApp._fitWindowToCard).
     */
    public static void configureTopCard(
            int heightPx, String overlayTitle, String overlayContent) {
        WindowSetup.width = WindowManager.LayoutParams.MATCH_PARENT;
        WindowSetup.height = heightPx;
        WindowSetup.enableDrag = false;
        WindowSetup.setGravityFromAlignment("topCenter");
        WindowSetup.setFlag("focusPointer");
        WindowSetup.overlayTitle = overlayTitle;
        WindowSetup.overlayContent = overlayContent == null ? "" : overlayContent;
        WindowSetup.positionGravity = "none";
        WindowSetup.setNotificationVisibility("visibilityPublic");
    }
}
