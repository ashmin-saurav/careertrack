import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AdBanner extends StatefulWidget {
  final AdSize size;
  final String? adUnitId;
  final DateTime? showAfter;

  // 🟢 NEW: Pass margin here.
  // It will ONLY be applied if the ad successfully loads.
  final EdgeInsetsGeometry? margin;

  const AdBanner({
    super.key,
    this.size = AdSize.banner,
    this.adUnitId,
    this.showAfter,
    this.margin,
  });

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  late String _adUnitId;
  bool _isMounting = true;
  Timer? _timer;

  // 🟢 PRODUCTION SETTINGS
  // Set to 24 to protect new accounts. Set to 0 to show ads immediately.
  static const int _hoursToHideAds = 24;
  static const String _prefsBox = "user_prefs";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 🟢 REAL AD ID (Replace with your Production ID if different)
    _adUnitId = widget.adUnitId ?? 'ca-app-pub-3116634693177302/1031044747';

    _startSmartLoad();
  }

  void _startSmartLoad() async {
    // 1. EXAM SHIELD CHECK
    if (widget.showAfter != null) {
      final now = DateTime.now();
      if (now.isBefore(widget.showAfter!)) {
        final waitDuration = widget.showAfter!.difference(now);
        await Future.delayed(waitDuration);
      }
    }

    if (!mounted || !_isMounting) return;

    // 2. SCROLL SAFETY CHECK (Wait 1s to prevent UI jank during initial scroll)
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted || !_isMounting) return;

    // 3. NEW USER CHECK & LOAD
    _checkHiveAndLoad();
  }

  Future<void> _checkHiveAndLoad() async {
    try {
      final box = await Hive.openBox(_prefsBox);
      final int? installTimestamp = box.get('first_install_timestamp');
      final int now = DateTime.now().millisecondsSinceEpoch;

      if (installTimestamp == null) {
        // First time user -> Save time
        await box.put('first_install_timestamp', now);

        // If 24h protection is ON, stop here.
        if (_hoursToHideAds > 0) return;
      } else {
        final DateTime installDate = DateTime.fromMillisecondsSinceEpoch(installTimestamp);
        final int hoursDiff = DateTime.now().difference(installDate).inHours;

        if (hoursDiff < _hoursToHideAds) {
          return; // App is too new, hide ad.
        }
      }

      // 4. LOAD THE AD
      _loadAd();

    } catch (e) {
      // If Hive fails, try loading anyway as a fallback
      _loadAd();
    }
  }

  void _loadAd() {
    if (_bannerAd != null) return;

    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      size: widget.size,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          _bannerAd = null;
          if (mounted) setState(() => _isLoaded = false);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _isMounting = false;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ⚡ EFFICIENCY: Dispose ad when app is paused (background) to save RAM
    if (state == AppLifecycleState.paused) {
      _bannerAd?.dispose();
      _bannerAd = null;
      if (mounted) setState(() => _isLoaded = false);
    } else if (state == AppLifecycleState.resumed) {
      // Reload when user returns
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _isMounting) _loadAd();
      });
    }
  }

  @override
  bool get wantKeepAlive => true; // Keeps ad alive in scrollable lists

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 🟢 ONLY SHOW CONTAINER IF AD IS LOADED
    if (_isLoaded && _bannerAd != null) {
      return Container(
        margin: widget.margin, // <--- Dynamic Margin (Applied only if loaded)
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        // ⚡ EFFICIENCY: RepaintBoundary isolates the ad's rendering from the rest of the list
        child: RepaintBoundary(
          child: AdWidget(ad: _bannerAd!),
        ),
      );
    }

    // 🔴 IF NO AD, RETURN 0 SIZE (No Grey Box)
    return const SizedBox.shrink();
  }
}