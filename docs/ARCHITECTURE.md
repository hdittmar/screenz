# Architecture

## Why a QR code and a local web page?

The Mac starts an HTTP server on a random port. The pairing QR contains its LAN IP address and a random 128-bit session token. Safari opens a bundled page with `<input type="file" accept="image/*" capture="environment">`, which delegates photo taking to the phone's camera/photo interface. There is no embedded live camera stream: [`getUserMedia` requires a secure context](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia), which plain HTTP on a LAN IP does not provide. The [HTML capture attribute](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/capture) supports the simpler photo-upload flow, with an existing-photo picker as a fallback.

Photos are sent only when the user taps Send. They are held in memory, processed on the Mac, and never intentionally saved or sent to a cloud service. Connections expire after 15 minutes. Requests require the session token and an allowed Host/Origin, have bounded headers and a 24 MB body limit, and time out after 60 seconds. No CORS access or third-party scripts are enabled. This prototype uses unencrypted local HTTP; use a trusted local network. A token prevents casual unauthorized requests but does not encrypt traffic.

If it cannot connect, allow Screenz through the macOS firewall/local-network permission prompt, check Wi-Fi client isolation, and try another IP using the Network address picker if present. Guest Wi-Fi, VPN routing, and different subnets can prevent direct connectivity. The MVP supports IPv4 LAN interfaces. A future remote pairing flow would need HTTPS and a relay; a native iPhone companion could add nearby discovery, but both add deployment work.

## Photo → arrangement

- AppKit draws one centered marker on each actual `NSScreen`. The payload includes a session ID and Core Graphics display ID.
- ImageIO decodes JPEG/PNG/HEIC and normalizes EXIF orientation; Vision detects all QR codes and their corners. Markers from other sessions, missing displays, duplicates, tiny codes, and heavily foreshortened codes are rejected.
- Known marker size in logical display points gives an approximate image-to-display scale. A nearest-neighbor tree estimates left/right/above/below relationships, then connects display edges, removing physical bezel gaps.
- The preview uses logical desktop dimensions, preserving Retina scaling, display rotation, and the existing main display. It changes only origins, not resolution, rotation, refresh rate, or scaling.
- Core Graphics [`CGConfigureDisplayOrigin`](https://developer.apple.com/documentation/coregraphics/cgconfiguredisplayorigin(_:_:_:_:)) applies all origins in a transaction. The test arrangement uses `CGConfigureOption.forAppOnly`; Keep commits it permanently. A timer reverts after 20 seconds, normal termination restores the previous arrangement, and macOS also unwinds application-only changes at process termination.

This is an approximate 2D layout estimate, not calibrated 3D reconstruction. Different physical pixel densities, angled monitors, camera roll, and perspective can distort offsets. Centered markers work best on a relatively flat, straight-on desk. Review is mandatory; overlapping or disconnected layouts cannot be applied. Some complex layouts require manual corrections. If displays are disconnected or their modes change mid-session, the app refuses to apply the stale proposal. Restoration may also fail after a hardware change; the app reports this and points to System Settings.
