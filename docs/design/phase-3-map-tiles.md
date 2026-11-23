# « Show tiles » on the maps, issue #246: design note

**Status: design**, written on 2026-11-23, before any code of [#246](https://github.com/Skyman21m/bull-market/issues/246), without any request to a tile server, a coordinator or a relay, and without running Tor or the app.
Where the code later differs, the code and its pull requests are right, and this note is updated.
The owner asked for the reference's « Show tiles » on both maps, off by default, the pinned point still randomized as today (issue #246, 2026-11-20); everything else here is a proposal of this note, said as « this note recommends », and the open questions are in § 9.
It was reviewed by an independent agent before merging; its findings are folded in.

Reference: RoboSats/robosats at commit babf62e (`babf62e2238f262182d0bf638496aaa53e286853`), the project's reference since #174 (`AGENTS.md:541`), frontend paths relative to `frontend/src/`.
Every line cited from the reference is at commit babf62e; of the files cited, only `components/Map/index.tsx` changed on the tiles since commit ff1998c (the tiles moved to `components/Map/osmTiles.ts`), and the locale files changed elsewhere than the lines cited.
Bull Market: `main` at `9a0d69ec6`. The `onion` package of `bull_sdk` is read at the commit the workspace pins (`1b01dc5e962c4c068fc4934b8125b839e2cd3264`, `pubspec.lock:185`).

**The decisive fact, in one line:** every SOCKS listener of the embedded Tor is opened onion-only (`packages/bull_tor/lib/src/data/onion_tor_backend.dart:17-31`, `SocksPolicy.onionOnly`, for the default listener at `:129-135` and `:405-419` with Snowflake, and for every session at `:309-313`), so the tiles of `tile.openstreetmap.org` cannot go through Tor without a change to `packages/bull_tor`; the change is small, since the policy is chosen per listener and the Tor client itself filters nothing (§ 3).

## 1. The reference

**Where.** Three maps carry the switch: the book's map (`components/Charts/MapChart/index.tsx`), the map where a maker chooses the meeting point (`components/Dialogs/F2fMap.tsx`, interactive, opened by `MakerForm.tsx:651`), and the same dialog read-only in an order's details (`components/OrderDetails/index.tsx:286-298`, opened at `:415`).
Bull Market has the first two; its order details show the place as numbers (`features/p2p/lib/src/ui/trade/trade_order_details.dart:15`, `:163`), so the third map is outside #246 (§ 10).

**The switch.** A small `Switch` with a picture icon, tooltip « Show tiles », at the right of the map's title (`F2fMap.tsx:105-125`, `MapChart/index.tsx:109-130`); off at first (`useState<boolean>(false)`, `F2fMap.tsx:40`, `MapChart/index.tsx:37`).
The first time it is turned on, a dialog opens instead (`F2fMap.tsx:116-121`); « Acknowledged » turns the tiles on, « Close » leaves them off; once acknowledged, the switch toggles freely.

**The dialog**, word for word (`F2fMap.tsx:75-98`, the same at `MapChart/index.tsx:61-84`):
- title « Download high resolution map? »;
- body « By doing so, you will be fetching map tiles from a third-party provider. Depending on your setup, private information might be leaked to servers outside the RoboSats federation. »;
- buttons « Close » and « Acknowledged ».

**Nothing is remembered.** The switch and the acknowledgment are component state (`useState`, `F2fMap.tsx:40-42`, `MapChart/index.tsx:37-39`): every new map starts without tiles and asks again.

**The tiles** (Leaflet `^1.9.4`, react-leaflet `^5.0.0`, `frontend/package.json:89`, `:99`):
- the address `OSM_TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'`, with no subdomain (`components/Map/osmTiles.ts:1`);
- each tile fetched by `loadOsmTileBlob` with the global `fetch`, the header `X-Requested-With: RoboSats` (`OSM_TILE_APP_ID`, `osmTiles.ts:6-12`), `referrerPolicy: 'no-referrer'`, an `AbortController` that drops the tiles leaving the view (`osmTiles.ts:14-34`, `Map/index.tsx:30-76`); any status but `2xx` is a failed tile (`osmTiles.ts:16-18`), so a tile OSM refuses with HTTP 200 and an error picture (§ 4) is shown as it comes;
- the credit « © OpenStreetMap contributors » shown on the map (`OSM_TILE_ATTRIBUTION`, `osmTiles.ts:3-4`, its own `Control.Attribution({ prefix: false })`, `Map/index.tsx:78-93`, the map's default control staying off, `:242`);
- the tiles **in place of** the bundled countries, never under them (`{!useTiles && worldmap && <GeoJSON …>}` then `{useTiles && <OsmTiles />}`, `Map/index.tsx:245-256`);
- `maxZoom={15}` (`:239`); the book's map opens at zoom 1 (`:241`), the meeting point's at 6 on a saved point and at 2 without one (`MakerForm.tsx:664`), an order's place at 6 (`OrderDetails/index.tsx:291`);
- no cache of its own: whatever the browser or the WebView keeps.

**Where the tile requests go, client by client** (the most important fact of this section):
- **Desktop app**: through Tor. `desktopApp/index.ts:110-113` sets `socks://localhost:9050`, the Tor it starts, as the proxy of the whole Electron session, so the tiles leave by a Tor exit relay, with Electron's browser User-Agent.
- **Android app**: **outside Tor, established by the code, not observed on a device.** The frontend runs in a WebView loaded from `file:///android_asset/index.html` (`android/app/src/main/java/com/robosats/MainActivity.kt:445`); Tor is the proxy of the OkHttp client behind the JavaScript bridge only (`HttpClientManager.setDefaultProxy`, `:289`); the WebView has no proxy (no `ProxyController` anywhere in `android/`), and the client installed once Tor is up overrides `shouldOverrideUrlLoading` only, with no `shouldInterceptRequest` (`:361-387`), so the tiles' `fetch` goes through the WebView's own network stack: the name resolved by the phone's DNS in clear, then the request from the phone's IP address, with the User-Agent `AndroidRobosats` (`:435`), `X-Requested-With: RoboSats`, and the cache off (`LOAD_NO_CACHE`, `:492`).
  The app's own agent notes say the opposite (`android/app/src/main/java/com/robosats/AGENTS.md:27-29`: « shouldInterceptRequest: allows file:///android_asset/ only; all other requests blocked »); the code wins, and if the notes were right the tiles would not show at all. The exceptions are outside the app: a system VPN, Orbot as a VPN (the « Use Orbot » option, `settings_use_proxy=false`), or a proxy set for the whole phone.
- **Web, over the onion**: the browser fetches the tiles itself. In Tor Browser they leave by a Tor exit, outside the federation; in an ordinary browser on the self-hosted client (`nodeapp/README.md`: only the API goes through the node's Tor) they leave in clear. This is the « Depending on your setup » of the dialog.

## 2. Today in Bull Market

**What draws the maps.** Both maps are drawn by the app, with no map dependency and no request (`AGENTS.md`, « The Map view of the book (#30) »): `MapChartView` (`features/p2p/lib/src/ui/map_chart_view.dart:30`) for the book, `LocationMapDialog` (`ui/location_map_dialog.dart:21`) for the meeting point, both painting with `MapChartPainter.paintWorld` and `paintPin` (`map_chart_view.dart:911`, `:943`; the dialog's `_LocationPainter`, `location_map_dialog.dart:318`).
The world is Natural Earth's 1:110m countries, about 42 KB, bundled (`features/p2p/assets/map/world_110m.bin`, read by `WorldMap.parse`, `domain/world_map.dart`), in Web Mercator as Leaflet projects it, zooms 0 to 15 (`domain/web_mercator.dart`: `tileSize` 256, `maxZoom` 15).
So the projection, the camera (`MapCamera`, `map_chart_view.dart:541`) and the tile size are already Leaflet's: a tile `z/x/y` maps onto the painter's world square with no new mathematics.

**The pinned point.** `MeetingPoint.randomized` (`domain/meeting_point.dart:17-29`) moves the place tapped by up to 0.05° on each axis (up to about 5.5 km north or south, less east or west away from the equator, so up to about 7.8 km diagonally at the equator), from `Random.secure` (`p2p_locator.dart:152`), then rounds it; the place tapped never leaves the dialog. Nothing reads the device's position; no permission is asked. #246 changes none of this.

**How the feature reaches the network today.** `TorCoordinatorTransport` (`data/tor_coordinator_transport.dart`) sends every coordinator request and every relay publication through the embedded Tor:
- each session comes from `tor().embedded.sessions.open()` (`:180`), a « circuit-isolated SOCKS route » of its own (`packages/bull_tor/lib/src/domain/entities/tor_session.dart`), with its own `HttpClient` built by `TorHttpClientFactory` (`packages/bull_tor/lib/src/data/tor_http_client_factory.dart:23-64`), whose only connection factory is SOCKS5, the host name sent to Tor unresolved, TLS done over the SOCKS socket for `https` (`:46-49`);
- one session per coordinator origin for the anonymous reads, one more per coordinator and robot for a robot's requests, so nothing ties a robot to another robot or to the anonymous reads (doc comment, `:88-91`);
- only `http` to a `.onion` host (`:110`, `_isOnion` `:209`), no `User-Agent` (decision of 2026-11-10, `:128-130`), `Accept-Encoding: identity`; the relay outcome is logged as a fixed label, never a relay, a robot or an event (`:125`).

**What fences it below.** In the `onion` package of `bull_sdk`, the policy belongs to each SOCKS listener: `TorSession::start(…, policy, …)` (`rust/src/api/session.rs:67-91`), checked on every `CONNECT` (`socks.rs:176`, `policy.allows(&addr)`, else `NOT_ALLOWED`); `SocksPolicy::Any` relays any destination and is the package's default, `OnionOnly` only hosts ending in `.onion` (`session.rs:20-54`, the Dart `SocksPolicy.any` and `.onionOnly`, `lib/src/rust/api/session.dart:30`); the Arti client itself is configured with `allow_onion_addrs(true)` and no destination filter (`client.rs:141-143`), and `open_session_with_connect_timeout(socks_port, policy, …)` takes the policy for each new session (`client.rs:198-222`).
`bull_tor` chooses `onionOnly` for every listener it opens (`onion_tor_backend.dart:31`), « refusing non-onion destinations » because a loopback SOCKS port has no authentication and any app on the device that finds it can use it (`:17-30`, the same warning at `session.rs:32-37`).

## 3. Fetching the tiles through Tor

**Not possible without changing `packages/bull_tor`.** Every Tor session the feature can open is onion-only, and no onion service of OpenStreetMap's tiles was found (§ 4).
A tile request sent through today's path is refused at the SOCKS step (`NOT_ALLOWED`), so nothing leaks, and nothing shows.

**The options**, none of which this note may carry out:
- **A. A narrow change to `bull_tor`, feasible on paper, not tried**: a second way to open a session, with `SocksPolicy.any`, used only for tiles; every other listener stays onion-only. It touches `bull_tor` alone (`OnionTorBackend.openSession`, `onion_tor_backend.dart:298-325`, and the `TorSessions` facade, `tor_controller.dart:60-66`), not `bull_sdk`, which already takes the policy per session (§ 2). Cost: a change to Bull's own package, to carry across every update from Bull's releases, which this fork follows; and, while such a session is open, its loopback port lets any app of the phone that finds it reach any website through Tor, from a Tor exit, without seeing anything of the tiles (TLS, its own streams): the exposure `onion_tor_backend.dart:17-30` narrows, small but real, so the session is opened only while tiles are shown and closed at once after.
- **B. A second Tor client started by the feature itself** through `bull_sdk`, with `any`: no change to `bull_tor`, but a second bootstrap (Tor took 62 s on 2026-11-10, `tor_coordinator_transport.dart:27`), twice the memory and battery, the same loopback exposure, and a feature reaching past `tor.dart`, which the package forbids (`packages/bull_tor/lib/tor.dart`, header). This note does not recommend it.
- **C. Outside Tor**, as the reference's Android app does by its code. For it: no change to Bull's code, faster, exactly what the reference's Android app does. Against it: the provider sees the phone's IP address and the DNS asks the name in clear. The owner's rule forbids it unless he decides it knowingly.
- **D. No tiles yet**: the switch is not offered, as today.
- Not an option for everyone: the user's own Tor, such as Orbot, which Bull can verify for its Electrum servers (`ExternalTor`, `tor_controller.dart:68-75`) and which filters nothing; the P2P feature uses only the embedded Tor (`tor_coordinator_transport.dart:180`), and this path would serve only the users who run one.

**If A is chosen, the rules of this note:**
- **Isolation**: one tile session per map opened with tiles, never used for anything else, closed when the map closes or the switch goes off; never a robot's session nor an anonymous coordinator session; Arti keeps the circuits of two sessions apart (`session.rs:56-61`, `isolated_client`), so the tile server cannot tie two openings, two robots, or a robot to its coordinator requests by a shared circuit.
- **Never outside Tor**: the tile client is built only from a `TorSession`'s endpoint (`TorHttpClientFactory.create` takes no null, `tor_http_client_factory.dart:13-18`); the tile source accepts only `https://tile.openstreetmap.org/{z}/{x}/{y}.png` with whole `z` from 0 to 15 and `x`, `y` within the zoom; no redirect followed; a response bounded in size (a tile is a few tens of KB) and decoded only as PNG.
- **Never logged**: no log line holds a tile's URL, its `z`, `x`, `y` or the view's bounds; only a fixed outcome label (loaded, refused, failed), as the relay outcome (`tor_coordinator_transport.dart:125`); a test pins it.
- **Tor not ready**: the switch can be turned on; the session waits for Tor as the coordinator requests do (`P2pTorState`, `coordinatorRequestDeadline`); a tile not there yet or failed leaves the countries drawn in its square; when the session cannot open or tiles fail, one short line « Map tiles unavailable » (the app's text, the reference having none), and the next pan or zoom tries again on a new session; never a fallback outside Tor.
- **Speed**: not measured. Each tile is one HTTPS request through a Tor exit; a phone screen at one zoom needs about 6 to 20 tiles.

## 4. The tile provider

Pages read on 2026-11-23:
- the tile usage policy, <https://operations.osmfoundation.org/policies/tiles/> (no date shown);
- « Blocked tiles », <https://wiki.openstreetmap.org/wiki/Blocked_tiles> (last edited 2026-11-12);
- « Technical updates to the tile.openstreetmap.org service », community.openstreetmap.org, topic 133421 (2025-07-30);
- the OSMF privacy policy, <https://osmfoundation.org/wiki/Privacy_Policy> (last edited 2026-01-25).

What the policy asks of an app:
- the exact URL `https://tile.openstreetmap.org/{z}/{x}/{y}.png`, as the reference uses at commit babf62e; other hosts « may be slower or withdrawn without notice »;
- « a distinct, stable User-Agent naming your app »; a library's default (Dart's own, or flutter_map's `flutter_map (unknown)`) « will be blocked », and never another app's or a browser's;
- a `Referer` from websites; « Native apps usually do not have a referer, this is ok »;
- honour `Cache-Control`, `Expires` and `ETag`, « If your cache cannot read them, cache each tile for at least 7 days », « Use Conditional Requests using `If-None-Match` and `If-Modified-Since` when requesting tiles that have expired », « Keep a sufficient local cache to ensure that repeat views do not unneccessarily re-download tiles », never send `no-cache`;
- no bulk download, no prefetch of tiles not in view, no offline use;
- the attribution « clearly on the map », not hidden;
- under « You must not »: « tunnel all clients behind a single, anonymous identity » (said of proxies); caching proxies « generally » not recommended;
- best effort, « no SLA », and blocks without notice when use degrades the service; since 2025-07-30, a refused tile comes back as an error picture with HTTP 200 and an `x-blocked` header;
- OSMF « publish[es] anonymised, aggregated usage data for research and operations, including summary data on tiles accessed and websites/apps using the service ».

What it says of Tor: nothing; Tor, VPNs and exit relays are not mentioned.
What is known publicly: the wiki says Tor Browser sends no `Referer` from onion sites and suggests `X-Requested-With`, the header the reference sends, or another provider; the Tor blocks found (captchas, a Cloudflare challenge) concern the website and the editing API, not the tiles, which a community thread says Fastly serves.
**Not established** (no request was made): whether `tile.openstreetmap.org` serves requests from Tor exits today, at what speed, whether its automatic `Referer` block applies to a native app with its own User-Agent, and how long tile logs are kept (the privacy policy does not say).
No official onion service of the tiles was found.

## 5. What the provider learns

For each tile request through Tor (option A):
- **the provider** (OSMF and its CDN): the exit relay's IP address, not the phone's; the tile's zoom, `x` and `y`, so the area looked at, down to one tile of zoom 15 (about 1.2 km wide at the equator, less towards the poles), so a neighbourhood, at street level; the time; the headers sent: the app's name (§ 9, question 2), no `Referer`, no cookie;
- **the exit relay**: the host name `tile.openstreetmap.org` and the size and timing of each response, not the tiles' content (HTTPS); tiles differ in size, so a hostile exit, which anyone can run, could compare those sizes with the public tiles and guess some of the tiles loaded: a known attack on maps over HTTPS, which needs effort and a chance pick of that exit;
- **a network observer near the phone**: Tor traffic only, no DNS query.

**What it reveals of a meeting point.** The coordinator publishes the point moved by up to 0.05° on each axis (§ 2), but the tiles the maker loads to aim show the true neighbourhood, at up to zoom 15, a few minutes before an order whose point lies within about 5.5 km on each axis appears in the public book. Whoever holds the provider's logs and reads the book can match the two by time and place and so undo much of the randomization, down to about the width of a tile; through Tor, without learning who the maker is.
On the book's map, the areas looked at say where the user looks for a trade.

**What reduces it**: Tor (no IP address); no `Referer`, and an app name shared by every user of the app; a new session per opening; the zoom capped at 15, as the reference; only the tiles in view, no neighbouring tiles fetched ahead; the cache in memory (§ 7), so a tile seen again is not asked again.

**Compared with the reference** at commit babf62e: its Android app, by its code, gives the provider the phone's IP address, `AndroidRobosats` and `RoboSats` with every area looked at, and the phone's DNS resolver the name; its desktop app gives an exit address, Electron's browser User-Agent and `RoboSats`, as option A would with its own name; Tor Browser, an exit address.

## 6. The library

**flutter_map**, Leaflet's Dart counterpart (fleaflet.dev, BSD-3-Clause, 8.3.2 on pub.dev): not in Bull nor in the workspace's lock; it brings `latlong2`, `proj4dart`, `path_provider`, `uuid` and more; a disk cache on by default since 8.2 (up to 1 GB in the system's cache folder; `DisabledMapCachingProvider` turns it off); `NetworkTileProvider(httpClient: …)` takes a `package:http` client, so an `IOClient` over the Tor `HttpClient` would carry its requests; its weight was not measured.
Adopting it means rebuilding both maps on it: the camera, gestures, pins, groups (a plugin), screen-reader nodes and tests of #30 and #189, all already matching the reference.

**Tiles drawn by the existing painter**: a tile layer in `paintWorld`'s transform, drawn in place of the countries as the reference does: the tiles of the view at the whole zoom below the camera's (0 to 15), fetched by a `MapTileSource` port of the feature, decoded with `instantiateImageCodec`, drawn scaled, a repaint as each arrives, the requests for tiles that left the view dropped (the reference's `AbortController`).
No new dependency, the HTTP client fully the feature's own (session, headers, size bound, no disk), the gestures and pins untouched; the cost is a small tile cache and its tests.

**This note recommends the existing painter**: a library is admitted where the reference has one, but here it would replace reviewed work, bring a disk cache to switch off and a client to wrap, and change nothing the user sees.

## 7. Cache and storage

- **Memory only**: decoded tiles kept in a bounded cache (for instance 256 tiles, a few MB) for the life of the app's process, with their `ETag` and expiry so that an expired tile is asked again conditionally (`If-None-Match`); nothing written to disk; the tile session and its circuits are closed with the map.
- A disk cache would leave on the phone the list and pictures of every area looked at, the meeting place included, readable by whoever holds the unlocked phone or a backup; this note recommends against it.
- The policy expects tiles kept 7 days or per their headers; a memory cache honours the headers while the app runs and forgets at the next start. The volume is a few dozen tiles a session, far from bulk use. This shortfall is said in the pull request.
- A screenshot of a map with tiles shows the neighbourhood. The P2P screens protected from capture are the Garage and the chat (`ui/garage/garage_view.dart`, `ui/trade/chat_panel.dart`, `ScreenCaptureProtection`); this note recommends that the code's pull request say whether `LocationMapDialog` joins them while tiles show.
- `FEATURES.md` and `AGENTS.md` say, when the code comes: the request path, the session rule, the memory-only cache, the app's name, the attribution, the logging rule, and that #30's « no tile, no request » no longer holds once the switch is on.

## 8. The dialog and its texts

Taken word for word from the reference at commit babf62e, in every language the feature has, from the reference's locale files as the feature does:
- English (`frontend/static/locales/en.json:202-206`): « Show tiles », « Download high resolution map? », the body of § 1, « Close », « Acknowledged »;
- French (`fr.json:202-206`): « Afficher les tuiles », « Télécharger une carte haute résolution? », « Fermer », « Confirmer »; the body is left in English in the reference's French file (`:203`).

The reference's body stays true whichever way the tiles travel (« Depending on your setup » covers it), but it does not say what the provider learns. This note recommends keeping it whole and adding one line of the app's own under it, true for the option chosen (the owner's rule of 2026-11-20: explanations short, more behind « See details »):
- option A: « Through Tor: OpenStreetMap sees the area you look at, not your IP address. »;
- option C: « Not through Tor: OpenStreetMap sees your IP address and the area you look at. »

Deviations from the reference, each with its reason:
- the tiles through Tor, where the reference's Android app sends them outside Tor: the owner's rule (option A);
- the app's own name, `BullMarket`, where the reference sends `RoboSats`: the provider forbids taking another app's name (§ 9, question 2);
- a User-Agent naming the app, where the feature sends none to coordinators: the provider's policy for apps (§ 9, question 2);
- decoded tiles kept in memory for the app's life, where the reference keeps none of its own (`LOAD_NO_CACHE` on Android): the provider's policy, and fewer requests (§ 7);
- the countries drawn in the square of a tile not loaded yet or failed, where the reference shows the empty background: the map stays readable through Tor's delays;
- the line under the dialog's text, and « Map tiles unavailable »: the app's;
- no longer deviations at commit babf62e: the host without subdomain, the credit shown on the map, the tiles leaving the view dropped;
- kept as the reference: off by default, the dialog the first time on each map opened, nothing remembered, zoom up to 15, the tiles in place of the countries, the switch's place at the right of the title.

## 9. Decisions for the owner

1. **How do the tiles travel?** This note recommends A, a narrow change to `bull_tor` (a session that may leave Tor's onion services, opened only while tiles show), feasible on paper, not tried. The cost: a change to Bull's package to carry at each update, and, while tiles show, a door through which another app of the phone could reach websites by Tor. C (outside Tor, as RoboSats' Android app) is simpler and faster but gives the user's IP address to the provider; D costs the feature.
2. **What name does the app give the tile server?** The reference already names itself, `X-Requested-With: RoboSats` on every tile (`osmTiles.ts:6-12`), and its Android app sends the fixed User-Agent `AndroidRobosats`; OSM blocks apps with no name or a library's. This note recommends the same with the app's own name: `X-Requested-With: BullMarket` and the User-Agent `BullMarket`, fixed, without version, the same for every user, on tile requests only. The cost: the provider knows the requests come from this app; with few users, that alone narrows who looks.
3. **Where are tiles kept?** This note recommends memory only. The cost: below the provider's 7-day expectation, tiles asked again at each start; a disk cache would leave the areas looked at on the phone.
4. **The dialog**: this note recommends the reference's text whole plus one line of the app's, true for the option chosen (§ 8). The cost of the reference's text alone: the user is not told that the area looked at is seen.

Whatever the answers, showing the real map to aim at the meeting point undoes much of the point's randomization for whoever holds the provider's logs (§ 5).

## 10. Work plan

- **PR 1, only if question 1 is A**, in `packages/bull_tor`: the session with `SocksPolicy.any`, opened on request, closed by its owner, every other listener staying onion-only, with its tests and a security review of the loopback exposure.
- **PR 2**, in `features/p2p`: the `MapTileSource` port and its Tor adapter (one session per map, the URL template fixed, whole zooms 0 to 15, size bound, PNG only, `x-blocked` read as a failure, the app's name, conditional requests), the memory cache, the tile layer in `MapChartPainter` and `_LocationPainter`, the switch, the dialog and its texts in every language, the attribution, `FEATURES.md` and `AGENTS.md`.
- **Tests**, with a fake tile source and never a real request: no tile asked while the switch is off or before « Acknowledged »; the dialog again on a new map; only tiles in view and within zoom 15; nothing on disk; no tile address nor `z`, `x`, `y` in the logs; the session closed with the map and never shared with a coordinator session; a failed or blocked tile leaves the countries in its square and the line; the pinned point still moved exactly as today; an architecture test that the tile source builds its client only from a `TorSession`.
- **Review**: the usual independent review, with a privacy part (session isolation, headers, logs, no disk, no fallback outside Tor, the dialog's honesty, capture protection).
- **Limits for the trial guide**: tiles may be slow or refused through Tor; the provider sees the area looked at, which undoes much of the point's randomization; nothing is kept between starts; the order details still show the place as numbers.
- **Outside #246**: the read-only map of an order's place (`OrderDetails/index.tsx:286-298`) deserves its own issue, the owner's rule being that nothing out of scope goes without one.
