import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_player/video_player.dart';

import 'data/lucy_message_catalog.dart';
import 'data/level_up_models.dart';
import 'services/ai_service.dart';
import 'services/notification_service.dart';
import 'state/level_up_app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // The app must remain usable in guest mode until Firebase config files
    // are added for the TestFlight bundle.
  }
  await NotificationService.instance.initialize();
  await NotificationService.instance.scheduleDailyReminders(
    const ReminderSettings(),
  );
  runApp(const LevelUpApp());
}

class FutureImagePickerBridge {
  const FutureImagePickerBridge._();

  static const MethodChannel _channel = MethodChannel('levelup/photo_picker');

  static Future<String?> pickImage() async {
    if (!Platform.isIOS) return null;
    try {
      return await _channel.invokeMethod<String>('pickFutureImage');
    } on PlatformException {
      return null;
    }
  }
}

class LevelUpApp extends StatefulWidget {
  const LevelUpApp({super.key});

  @override
  State<LevelUpApp> createState() => _LevelUpAppState();
}

class _LevelUpAppState extends State<LevelUpApp> {
  late final LevelUpAppState _appState = LevelUpAppState()..load();

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LevelUpScope(
      notifier: _appState,
      child: MaterialApp(
        title: 'Level Up',
        debugShowCheckedModeBanner: false,
        builder: (context, child) => DefaultTextStyle.merge(
          style: const TextStyle(
            decoration: TextDecoration.none,
            decorationColor: Colors.transparent,
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: AppColors.background,
          fontFamily: 'SF Pro Display',
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.clay,
            brightness: Brightness.light,
          ),
        ),
        home: const LevelUpLaunch(),
      ),
    );
  }
}

class LevelUpLaunch extends StatefulWidget {
  const LevelUpLaunch({super.key});

  @override
  State<LevelUpLaunch> createState() => _LevelUpLaunchState();
}

class _LevelUpLaunchState extends State<LevelUpLaunch>
    with SingleTickerProviderStateMixin {
  static const _launchVideos = [
    'assets/videos/onboarding-video.mp4',
    'assets/videos/goal-achievement-celebration.mp4',
  ];

  VideoPlayerController? _videoController;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 18000),
  )..forward();
  bool _videoReady = false;
  bool _changingVideo = false;
  bool _didContinue = false;
  int _videoIndex = 0;
  int _videoLoadToken = 0;

  @override
  void initState() {
    super.initState();
    _loadVideo(0);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _continueToApp();
      }
    });
  }

  @override
  void dispose() {
    final controller = _videoController;
    _videoController = null;
    controller?.removeListener(_handleVideoProgress);
    unawaited(
      _disposeVideoController(controller, delay: const Duration(seconds: 2)),
    );
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadVideo(int index) async {
    final token = ++_videoLoadToken;
    final nextController = VideoPlayerController.asset(_launchVideos[index]);
    try {
      await nextController.initialize();
      if (!mounted || token != _videoLoadToken) {
        await nextController.dispose();
        return;
      }

      final oldController = _videoController;
      oldController?.removeListener(_handleVideoProgress);
      _videoIndex = index;
      _videoController = nextController;
      unawaited(
        _disposeVideoController(
          oldController,
          delay: const Duration(milliseconds: 700),
        ),
      );
      _videoController!
        ..setLooping(false)
        ..setVolume(0)
        ..addListener(_handleVideoProgress)
        ..play();

      setState(() {
        _videoReady = true;
        _changingVideo = false;
      });
    } catch (_) {
      await nextController.dispose();
      if (!mounted) return;
      setState(() {
        _videoReady = false;
        _changingVideo = false;
      });
    }
  }

  Future<void> _disposeVideoController(
    VideoPlayerController? controller, {
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    if (controller == null) return;
    try {
      await controller.pause();
    } catch (_) {
      return;
    }
    await Future<void>.delayed(delay);
    try {
      await controller.dispose();
    } catch (_) {
      // The native video player may already be gone during fast launch swaps.
    }
  }

  void _handleVideoProgress() {
    final controller = _videoController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _changingVideo ||
        _didContinue) {
      return;
    }

    final duration = controller.value.duration;
    if (duration == Duration.zero) return;

    final isFinished =
        controller.value.position >=
        duration - const Duration(milliseconds: 160);
    if (!isFinished) return;

    if (_videoIndex < _launchVideos.length - 1) {
      _changingVideo = true;
      _loadVideo(_videoIndex + 1);
      return;
    }

    _continueToApp();
  }

  void _continueToApp() {
    if (_didContinue || !mounted) return;
    _didContinue = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 560),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LevelUpStartupGate(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Animation<double> _interval(
    double begin,
    double end, {
    Curve curve = Curves.easeOutCubic,
  }) {
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, end, curve: curve),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoController = _videoController;
    final logoOpacity = _interval(.04, .22);
    final logoScale = Tween<double>(
      begin: .94,
      end: 1,
    ).animate(_interval(.04, .24));
    final firstText = _interval(.32, .48);
    final secondText = _interval(.62, .78);
    final lucyText = _interval(.80, .96);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
          children: [
            const LiquidBackground(),
            Positioned.fill(
              child: _videoReady && videoController != null
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: videoController.value.size.width,
                        height: videoController.value.size.height,
                        child: VideoPlayer(videoController),
                      ),
                    )
                  : AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: LaunchJourneyPainter(
                            progress: _controller.value,
                          ),
                          size: Size.infinite,
                        );
                      },
                    ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: .12),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 34),
                child: Column(
                  children: [
                    FadeTransition(
                      opacity: logoOpacity,
                      child: ScaleTransition(
                        scale: logoScale,
                        child: SizedBox(
                          width: 154,
                          height: 46,
                          child: Image.asset(
                            'assets/images/levelup_logo.png',
                            fit: BoxFit.fitWidth,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    FadeTransition(
                      opacity: firstText,
                      child: const Text(
                        'Every step matters.',
                        textAlign: TextAlign.center,
                        style: AppText.hero,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FadeTransition(
                      opacity: secondText,
                      child: const Text(
                        "Let's build your future.",
                        textAlign: TextAlign.center,
                        style: AppText.section,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FadeTransition(
                      opacity: lucyText,
                      child: GlassCard(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        borderRadius: 24,
                        opacity: .56,
                        child: Row(
                          children: const [
                            _IntroLucyAvatar(),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Hi 👋 I'm Lucy. I'll help you turn your vision into daily action.",
                                style: AppText.bodyStrong,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroLucyAvatar extends StatelessWidget {
  const _IntroLucyAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: .72),
        border: Border.all(color: Colors.white.withValues(alpha: .90)),
        boxShadow: [
          BoxShadow(
            color: AppColors.sage.withValues(alpha: .14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset('assets/images/lucy_portrait.png', fit: BoxFit.cover),
    );
  }
}

class LaunchJourneyPainter extends CustomPainter {
  LaunchJourneyPainter({required this.progress});

  final double progress;

  double _ease(double start, double end, [Curve curve = Curves.easeOutCubic]) {
    final t = ((progress - start) / (end - start)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final build = _ease(.10, .46);
    final person = _ease(.28, .64, Curves.easeInOutCubic);
    final reveal = _ease(.48, .82);
    final fade = progress < .94
        ? 1.0
        : (1 - ((progress - .94) / .06)).clamp(0.0, 1.0);

    final glowPaint = Paint()
      ..color = AppColors.sage.withValues(alpha: .10 * reveal * fade)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 56);
    canvas.drawCircle(
      Offset(size.width * .70, size.height * .34),
      116 + 18 * reveal,
      glowPaint,
    );

    final cloudPaint = Paint()
      ..color = Colors.white.withValues(alpha: .24 * fade);
    for (final cloud in [
      Offset(size.width * .18, size.height * .22),
      Offset(size.width * .82, size.height * .26),
      Offset(size.width * .26, size.height * .72),
    ]) {
      canvas.drawCircle(cloud, 52, cloudPaint);
      canvas.drawCircle(cloud.translate(34, 8), 40, cloudPaint);
      canvas.drawCircle(cloud.translate(-26, 10), 34, cloudPaint);
    }

    final mountainPaint = Paint()
      ..color = AppColors.sage.withValues(alpha: .10 * reveal * fade);
    final mountain = Path()
      ..moveTo(size.width * .05, size.height * .66)
      ..lineTo(size.width * .34, size.height * (.49 + .05 * (1 - reveal)))
      ..lineTo(size.width * .56, size.height * .66)
      ..lineTo(size.width * .73, size.height * (.52 + .05 * (1 - reveal)))
      ..lineTo(size.width * .98, size.height * .66)
      ..lineTo(size.width * .98, size.height)
      ..lineTo(size.width * .05, size.height)
      ..close();
    canvas.drawPath(mountain, mountainPaint);

    final baseX = size.width * .20;
    final baseY = size.height * .63;
    const stepCount = 6;
    final stepW = size.width * .20;
    final stepH = size.height * .035;

    for (var i = 0; i < stepCount; i++) {
      final local = ((build * stepCount) - i).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final eased = Curves.easeOutBack.transform(local);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          baseX + i * stepW * .40,
          baseY - i * stepH * 1.22 + (1 - eased) * 20,
          stepW * eased,
          stepH,
        ),
        const Radius.circular(10),
      );
      final shadow = Paint()
        ..color = Colors.black.withValues(alpha: .035 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
      canvas.drawRRect(rect.shift(const Offset(0, 5)), shadow);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = Color.lerp(
            AppColors.cream,
            AppColors.sage,
            i / 9,
          )!.withValues(alpha: (.86 - i * .035) * fade),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: .55 * fade),
      );
    }

    final stepPosition = person * 3.8;
    final x = baseX + stepPosition * stepW * .40 + 18;
    final y =
        baseY -
        stepPosition * stepH * 1.22 -
        22 -
        math.sin(person * math.pi * 4) * 4;
    final figure = Paint()
      ..color = AppColors.ink.withValues(alpha: _ease(.20, .34) * fade * .74)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(x, y - 18), 7, figure);
    canvas.drawLine(Offset(x, y - 10), Offset(x, y + 12), figure);
    canvas.drawLine(Offset(x, y - 2), Offset(x - 15, y + 8), figure);
    canvas.drawLine(Offset(x, y + 12), Offset(x - 14, y + 28), figure);
    canvas.drawLine(Offset(x, y + 12), Offset(x + 16, y + 24), figure);

    final flagBase = Offset(size.width * .78, size.height * .34);
    final flagOpacity = _ease(.58, .84) * fade;
    final flagPole = Paint()
      ..color = AppColors.sage.withValues(alpha: flagOpacity)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(flagBase, flagBase.translate(0, 48), flagPole);
    final flag = Path()
      ..moveTo(flagBase.dx, flagBase.dy + 3)
      ..lineTo(flagBase.dx + 34, flagBase.dy + 11)
      ..lineTo(flagBase.dx, flagBase.dy + 22)
      ..close();
    canvas.drawPath(
      flag,
      Paint()..color = AppColors.gold.withValues(alpha: flagOpacity),
    );
  }

  @override
  bool shouldRepaint(covariant LaunchJourneyPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class LevelUpStartupGate extends StatelessWidget {
  const LevelUpStartupGate({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = LevelUpScope.of(context);

    if (appState.isLoading) {
      return const Scaffold(
        body: Stack(
          children: [
            LiquidBackground(),
            Center(child: CupertinoActivityIndicator(radius: 14)),
          ],
        ),
      );
    }

    if (!appState.user.onboardingCompleted ||
        appState.user.name.trim().isEmpty) {
      return const OnboardingScreen();
    }

    return const LevelUpShell();
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _totalPages = 6;

  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();
  late final Map<String, TextEditingController> _areaVisionControllers = {
    for (final area in _lifeAreas)
      area: TextEditingController(text: _defaultAreaVision(area)),
  };
  int _page = 0;
  bool _isSubmitting = false;

  static const _lifeAreas = [
    'Health',
    'Finance',
    'Relationships',
    'Personal',
    'Career',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    for (final controller in _areaVisionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _next() {
    if (_page == 1 && _nameController.text.trim().isEmpty) return;
    if (_page == 3 &&
        _areaVisionControllers.values.every(
          (controller) => controller.text.trim().isEmpty,
        )) {
      return;
    }

    if (_page >= _totalPages - 1) {
      _finish();
      return;
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final appState = LevelUpScope.read(context);
    final goalId = 'goal_${DateTime.now().millisecondsSinceEpoch}';
    final areaVisions = {
      for (final area in _lifeAreas)
        area: _areaVisionControllers[area]!.text.trim(),
    };
    final mainVision = areaVisions.values
        .where((value) => value.trim().isNotEmpty)
        .join(' ');
    const title = 'Run 5 km without stopping';
    final firstGoal = Goal(
      id: goalId,
      category: 'HEALTH',
      title: title,
      detail: 'Jul 31, 2026',
      progress: .05,
      vision: areaVisions['Health']?.trim().isNotEmpty == true
          ? areaVisions['Health']!.trim()
          : _defaultAreaVision('Health'),
      timeline: 'Run 1 km daily -> Run 5 km without stopping',
      completed: false,
      milestones: const [],
    );

    await appState.completeOnboarding(
      name: _nameController.text.trim(),
      vision: mainVision.trim().isEmpty
          ? _defaultAreaVision('Health')
          : mainVision,
      identities: const [],
      areaVisions: areaVisions,
      firstGoal: firstGoal,
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 520),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LevelUpShell(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  static String _defaultAreaVision(String area) {
    return switch (area) {
      'Finance' => 'Build financial freedom',
      'Relationships' => 'Build deeper relationships',
      'Personal' => 'Become disciplined and calm',
      'Career' => 'Build my own mobile app',
      _ => 'Run a half marathon',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
          children: [
            const LiquidBackground(),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: OnboardingProgress(
                            current: _page,
                            total: _totalPages,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_page + 1}/$_totalPages',
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (value) => setState(() => _page = value),
                      children: [
                        _WelcomeStep(onNext: _next),
                        _NameStep(controller: _nameController),
                        _OnboardingLoginStep(onSkip: _next),
                        _LifeAreaVisionStep(
                          controllers: _areaVisionControllers,
                        ),
                        const _VisionGoalTaskStep(),
                        _ReadyStep(
                          name: _nameController.text.trim().isEmpty
                              ? 'there'
                              : _nameController.text.trim(),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                    child: GlassActionButton(
                      icon: _page >= _totalPages - 1
                          ? CupertinoIcons.check_mark_circled
                          : CupertinoIcons.arrow_right_circle,
                      label: _isSubmitting
                          ? 'Preparing...'
                          : _page >= _totalPages - 1
                          ? 'Create first goals'
                          : 'Continue',
                      strong: true,
                      onTap: _isSubmitting ? null : _next,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    super.key,
    required this.current,
    required this.total,
  });

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 7,
        value: (current + 1) / total,
        backgroundColor: Colors.white.withValues(alpha: .48),
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.sage),
      ),
    );
  }
}

class _OnboardingShell extends StatelessWidget {
  const _OnboardingShell({
    required this.eyebrow,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 22),
          Text(eyebrow, style: AppText.eyebrow),
          const SizedBox(height: 14),
          Text(title, style: AppText.hero),
          if (subtitle != null) ...[
            const SizedBox(height: 12),
            Text(subtitle!, style: AppText.body),
          ],
          const SizedBox(height: 28),
          child,
        ],
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _OnboardingShell(
      eyebrow: 'LEVEL UP',
      title: 'Become the person you want to be.',
      subtitle:
          'Tiny actions. Visible progress. A future self you can actually move toward.',
      child: Column(
        children: [
          const MountainPathImage(height: 260),
          const SizedBox(height: 18),
          Stack(
            clipBehavior: Clip.none,
            children: [
              const GlassCard(
                borderRadius: 24,
                padding: EdgeInsets.all(16),
                child: Text(
                  "Hi 👋 I'm Lucy. I'll help you turn your vision into daily action.",
                  style: AppText.bodyStrong,
                ),
              ),
              const Positioned(
                right: 14,
                bottom: -24,
                child: _IntroLucyAvatar(),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class FutureVisionHeaderImage extends StatelessWidget {
  const FutureVisionHeaderImage({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/vision_transparent_crop.png',
      width: 130,
      height: 130,
      fit: BoxFit.cover,
      alignment: Alignment.center,
    );
  }
}

class _OnboardingLoginStep extends StatelessWidget {
  const _OnboardingLoginStep({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return _OnboardingShell(
      eyebrow: 'ACCOUNT',
      title: 'Save your progress when you are ready.',
      subtitle:
          'Sign in later to sync your goals. For now, guest mode keeps testing fast and local.',
      child: Column(
        children: [
          const AccountPreviewCard(
            session: AuthSession(
              userId: 'guest_preview',
              provider: AuthProvider.guest,
              displayName: 'Guest',
            ),
            user: UserProfile(
              name: '',
              vision: '',
              identities: [],
              streakDays: 0,
              onboardingCompleted: false,
            ),
          ),
          const SizedBox(height: 14),
          GlassActionButton(
            icon: CupertinoIcons.person_crop_circle_badge_checkmark,
            label: 'Continue with Google',
            strong: true,
            onTap: () => _showOnboardingSignInDialog(
              context,
              LevelUpScope.read(context).signInWithGoogle,
            ),
          ),
          const SizedBox(height: 10),
          GlassActionButton(
            icon: CupertinoIcons.arrow_right_circle,
            label: 'Skip for now',
            onTap: onSkip,
          ),
        ],
      ),
    );
  }

  Future<void> _showOnboardingSignInDialog(
    BuildContext context,
    Future<String> Function() action,
  ) async {
    final message = await action();
    if (!context.mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Account'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _NameStep extends StatelessWidget {
  const _NameStep({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return _OnboardingShell(
      eyebrow: 'PERSONALIZE',
      title: 'What should we call you?',
      subtitle:
          'Lucy will personalize your journey and make the app feel like it was built for you.',
      child: GlassCard(
        borderRadius: 28,
        padding: const EdgeInsets.all(20),
        child: GoalFormField(label: 'Your name', controller: controller),
      ),
    );
  }
}

class _LifeAreaVisionStep extends StatelessWidget {
  const _LifeAreaVisionStep({required this.controllers});

  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    return _OnboardingShell(
      eyebrow: 'FUTURE IDENTITY',
      title: 'Who do you want to become?',
      subtitle:
          'Write a simple vision for each life area. You can edit these later in Future Me.',
      child: GlassCard(
        borderRadius: 28,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in controllers.entries) ...[
              Text(
                entry.key,
                style: AppText.bodyStrong.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              CupertinoTextField(
                controller: entry.value,
                onTap: () {
                  final defaultText = _OnboardingScreenState._defaultAreaVision(
                    entry.key,
                  );
                  if (entry.value.text == defaultText) entry.value.clear();
                },
                minLines: 1,
                maxLines: 1,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: appTextInputFormatters,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 12,
                ),
                style: AppText.bodyStrong,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .52),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .72),
                  ),
                ),
              ),
              if (entry.key != controllers.keys.last)
                const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _VisionGoalTaskStep extends StatelessWidget {
  const _VisionGoalTaskStep();

  @override
  Widget build(BuildContext context) {
    return _OnboardingShell(
      eyebrow: 'HOW LEVEL UP WORKS',
      title: 'Your future becomes real through steps.',
      subtitle:
          'Before we build your journey, here is the simple relationship between vision, goals and daily tasks.',
      child: Column(children: const [VisionGoalTaskCard()]),
    );
  }
}

class VisionGoalTaskCard extends StatelessWidget {
  const VisionGoalTaskCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      borderRadius: 30,
      opacity: .54,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/images/vision_goals_tasks_nested.png',
              fit: BoxFit.fitWidth,
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }
}

class VisionGoalTaskPainter extends CustomPainter {
  const VisionGoalTaskPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stepPaint = Paint()..color = AppColors.cream.withValues(alpha: .94);
    final activePaint = Paint()..color = AppColors.sage.withValues(alpha: .30);
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: .045)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final baseX = size.width * .18;
    final baseY = size.height * .78;
    final stepW = size.width * .24;
    final stepH = size.height * .10;

    for (var i = 0; i < 4; i++) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          baseX + i * stepW * .55,
          baseY - i * stepH * 1.15,
          stepW,
          stepH,
        ),
        const Radius.circular(9),
      );
      canvas.drawRRect(rect.shift(const Offset(0, 5)), shadowPaint);
      canvas.drawRRect(rect, stepPaint);
      if (i < 2) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              rect.left + rect.width * .25,
              rect.top,
              rect.width * .5,
              rect.height,
            ),
            const Radius.circular(7),
          ),
          activePaint,
        );
      }
    }

    final future = Offset(size.width * .76, size.height * .22);
    canvas.drawCircle(
      future,
      34,
      Paint()..color = AppColors.gold.withValues(alpha: .18),
    );
    canvas.drawCircle(
      future,
      20,
      Paint()..color = Colors.white.withValues(alpha: .78),
    );
    final flagPaint = Paint()
      ..color = AppColors.sage
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      future.translate(-4, 6),
      future.translate(-4, 38),
      flagPaint,
    );
    final flag = Path()
      ..moveTo(future.dx - 4, future.dy + 8)
      ..lineTo(future.dx + 22, future.dy + 14)
      ..lineTo(future.dx - 4, future.dy + 21)
      ..close();
    canvas.drawPath(
      flag,
      Paint()..color = AppColors.sage.withValues(alpha: .82),
    );

    final task = Paint()
      ..color = AppColors.ink.withValues(alpha: .72)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final p = Offset(baseX + 20, baseY - 18);
    canvas.drawCircle(p.translate(0, -18), 6, task);
    canvas.drawLine(p.translate(0, -10), p.translate(0, 12), task);
    canvas.drawLine(p.translate(0, 0), p.translate(16, 7), task);
    canvas.drawLine(p.translate(0, 12), p.translate(-12, 28), task);
    canvas.drawLine(p.translate(0, 12), p.translate(16, 26), task);
  }

  @override
  bool shouldRepaint(covariant VisionGoalTaskPainter oldDelegate) => false;
}

class _ReadyStep extends StatelessWidget {
  const _ReadyStep({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return _OnboardingShell(
      eyebrow: 'READY',
      title: 'Welcome, $name.',
      subtitle: 'Your journey begins with one visible step today.',
      child: const GlassCard(
        borderRadius: 30,
        padding: EdgeInsets.all(22),
        child: Column(
          children: [
            _ChecklistItem(text: 'Vision created', done: true),
            _ChecklistItem(text: 'Goals created'),
            _ChecklistItem(text: 'First task ready'),
          ],
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({required this.text, this.done = false});

  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: done
                  ? AppColors.sage.withValues(alpha: .22)
                  : Colors.white.withValues(alpha: .34),
              shape: BoxShape.circle,
              border: Border.all(
                color: done ? AppColors.sage : AppColors.hairline,
              ),
            ),
            child: done
                ? const Icon(
                    CupertinoIcons.check_mark,
                    size: 15,
                    color: AppColors.sage,
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppText.bodyStrong)),
        ],
      ),
    );
  }
}

class OnboardingStairsPainter extends CustomPainter {
  const OnboardingStairsPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final stepPaint = Paint()..color = AppColors.sage.withValues(alpha: .58);
    final shinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: .5);

    final baseY = size.height * .72;
    final baseX = size.width * .2;
    const stepH = 28.0;
    final stepW = size.width * .22;

    for (var i = 0; i < 5; i++) {
      final local = ((progress * 5) - i).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final eased = Curves.easeOutCubic.transform(local);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          baseX + i * 28,
          baseY - i * stepH + (1 - eased) * 16,
          stepW + i * 10,
          17,
        ),
        const Radius.circular(10),
      );
      canvas.drawRRect(rect, stepPaint);
      canvas.drawRRect(rect, shinePaint);
    }

    final flagPole = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = AppColors.clay.withValues(alpha: .72);
    final top = Offset(baseX + 4 * 28 + stepW + 26, baseY - 4 * stepH - 44);
    canvas.drawLine(top, top.translate(0, 58), flagPole);

    final flagPath = Path()
      ..moveTo(top.dx, top.dy + 4)
      ..lineTo(top.dx + 38, top.dy + 14)
      ..lineTo(top.dx, top.dy + 26)
      ..close();
    canvas.drawPath(
      flagPath,
      Paint()..color = AppColors.gold.withValues(alpha: .72),
    );

    final personCenter = Offset(baseX + 18, baseY - 28);
    canvas.drawCircle(
      personCenter.translate(0, -18),
      7,
      Paint()..color = AppColors.ink.withValues(alpha: .72),
    );
    canvas.drawLine(
      personCenter.translate(0, -10),
      personCenter.translate(0, 12),
      Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = AppColors.ink.withValues(alpha: .72),
    );

    final glowPaint = Paint()
      ..color = AppColors.gold.withValues(alpha: .08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 38);
    canvas.drawCircle(
      Offset(size.width * .73, size.height * .36),
      72,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant OnboardingStairsPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class LevelUpShell extends StatefulWidget {
  const LevelUpShell({super.key});

  @override
  State<LevelUpShell> createState() => _LevelUpShellState();
}

class _LevelUpShellState extends State<LevelUpShell> {
  int _tab = 0;
  int _goalsResetToken = 0;
  bool _showGoalDetail = false;
  bool _showGoalCompletion = false;
  bool _showMonthOverview = false;
  String? _selectedGoalId;
  bool _lucyOpen = false;
  bool _lucyUnread = true;
  bool _celebrating = false;
  bool _dayCompleteOpen = false;
  String? _lucyMessage;

  void _showLucy(String message) {
    setState(() {
      _lucyMessage = message;
      _lucyOpen = true;
      _lucyUnread = false;
    });
  }

  void _celebrateTask() {
    final firstName = LevelUpScope.read(context).user.firstName;
    _showLucy(LucyMessageCatalog.taskCompleted(firstName));
    setState(() => _celebrating = true);
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _celebrating = false);
    });
  }

  void _openDayComplete() {
    setState(() {
      _dayCompleteOpen = true;
      _celebrating = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _celebrating = false);
    });
  }

  void _closeDayComplete() {
    setState(() => _dayCompleteOpen = false);
  }

  void _dayCompleteSeeGoals() {
    setState(() {
      _dayCompleteOpen = false;
      _tab = 1;
      _showGoalDetail = false;
      _showGoalCompletion = false;
      _selectedGoalId = null;
    });
  }

  void _openGoals() {
    setState(() {
      _tab = 1;
      _showGoalDetail = false;
      _showGoalCompletion = false;
      _selectedGoalId = null;
    });
  }

  void _openGoalDetail(String goalId) {
    setState(() {
      if (_tab != 2) _tab = 1;
      _selectedGoalId = goalId;
      _showGoalDetail = true;
      _showGoalCompletion = false;
    });
  }

  void _openGoalCompletion(String goalId) {
    setState(() {
      _selectedGoalId = goalId;
      _showGoalDetail = false;
      _showGoalCompletion = true;
    });
  }

  void _closeGoalFlow() {
    setState(() {
      _showGoalCompletion = false;
      _showGoalDetail = false;
      _selectedGoalId = null;
    });
  }

  void _openMonthOverview() {
    setState(() {
      _tab = 0;
      _showMonthOverview = true;
      _lucyOpen = false;
      _lucyMessage = null;
    });
  }

  void _closeMonthOverview() {
    setState(() => _showMonthOverview = false);
  }

  @override
  Widget build(BuildContext context) {
    final appState = LevelUpScope.of(context);
    final firstName = appState.user.firstName.isEmpty
        ? 'there'
        : appState.user.firstName;
    final currentLucyMessage =
        _lucyMessage ??
        (_showMonthOverview
            ? LucyMessageCatalog.calendarPattern
            : LucyMessageCatalog.home(firstName));
    final isSubpage =
        _showGoalDetail || _showGoalCompletion || _showMonthOverview;
    final pages = [
      _showMonthOverview
          ? MonthOverviewScreen(onBack: _closeMonthOverview)
          : HomeScreen(
              onOpenGoal: _openGoalDetail,
              onOpenMonth: _openMonthOverview,
              onTaskCompleted: _celebrateTask,
              onDayCompleted: _openDayComplete,
            ),
      _tab == 1 && _showGoalCompletion
          ? GoalCompletionScreen(
              goalId: _selectedGoalId,
              backLabel: 'Back to Goals',
              onDone: _openGoals,
              onClose: _closeGoalFlow,
              onAddNew: _openGoals,
            )
          : _tab == 1 && _showGoalDetail
          ? GoalDetailScreen(
              goalId: _selectedGoalId,
              onBack: _openGoals,
              onGoalCompleted: _openGoalCompletion,
            )
          : GoalsScreen(
              onOpenGoal: _openGoalDetail,
              resetToken: _goalsResetToken,
            ),
      _tab == 2 && _showGoalCompletion
          ? GoalCompletionScreen(
              goalId: _selectedGoalId,
              backLabel: 'Back to Future Me',
              onDone: _closeGoalFlow,
              onClose: _closeGoalFlow,
              onAddNew: _openGoals,
            )
          : _tab == 2 && _showGoalDetail
          ? GoalDetailScreen(
              goalId: _selectedGoalId,
              onBack: _closeGoalFlow,
              onGoalCompleted: _openGoalCompletion,
            )
          : FutureMeScreen(onOpenGoal: _openGoalDetail),
      const MotivateScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          const LiquidBackground(),
          IndexedStack(index: _tab, children: pages),
          if (!isSubpage)
            Positioned(
              top: MediaQuery.of(context).padding.top + 18,
              right: 20,
              child: LucyAvatarButton(
                hasUnread: _lucyUnread,
                onTap: () => _showLucy(currentLucyMessage),
              ),
            ),
          if (_lucyOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _lucyOpen = false),
                child: const SizedBox.expand(),
              ),
            ),
          if (_lucyOpen)
            Positioned(
              top: MediaQuery.of(context).padding.top + 72,
              left: 48,
              right: 20,
              child: LucyCoachMessage(
                message: currentLucyMessage,
                onTap: () => setState(() => _lucyOpen = false),
              ),
            ),
          if (_celebrating) const CelebrationOverlay(),
          if (_dayCompleteOpen)
            DayCompleteOverlay(
              onClose: _closeDayComplete,
              onSeeGoals: _dayCompleteSeeGoals,
            ),
          if (!isSubpage)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: GlassTabBar(
                  currentIndex: _tab,
                  onTap: (index) {
                    setState(() {
                      if (_tab == 1 && index != 1) {
                        _goalsResetToken++;
                      }
                      _tab = index;
                      if (index != 1) {
                        _showGoalDetail = false;
                        _showGoalCompletion = false;
                        _selectedGoalId = null;
                      }
                      if (index != 0) _showMonthOverview = false;
                    });
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenGoal,
    required this.onOpenMonth,
    required this.onTaskCompleted,
    required this.onDayCompleted,
  });

  final ValueChanged<String> onOpenGoal;
  final VoidCallback onOpenMonth;
  final VoidCallback onTaskCompleted;
  final VoidCallback onDayCompleted;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _selectedDate = _dateOnly(DateTime.now());

  IconData _taskIcon(String category) {
    switch (category.toUpperCase()) {
      case 'HEALTH':
        return Icons.fitness_center;
      case 'CAREER':
        return CupertinoIcons.book;
      case 'FINANCE':
        return CupertinoIcons.money_pound_circle;
      case 'PERSONAL':
      case 'RELATIONSHIPS':
      case 'FAMILY':
        return CupertinoIcons.heart;
      case 'BALANCE':
      case 'LIFESTYLE':
        return CupertinoIcons.moon_stars;
      default:
        return CupertinoIcons.sparkles;
    }
  }

  String _greetingForNow(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _toggleTask(BuildContext context, DailyTask task) async {
    final wasCompleted = task.completed;
    final appState = LevelUpScope.read(context);
    await appState.toggleTask(task.id);
    if (!wasCompleted) {
      final allDone =
          appState.todayTasks.isNotEmpty &&
          appState.todayTasks.every((item) => item.completed);
      if (allDone) {
        widget.onDayCompleted();
      } else {
        widget.onTaskCompleted();
      }
    }
  }

  void _showAddTask(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => AddDailyTaskSheet(
        goals: LevelUpScope.read(context).goals,
        initialDate: _selectedDate,
        onCreate: (creation) async {
          final appState = LevelUpScope.read(context);
          var goalId = creation.goalId;
          if (creation.newGoal != null) {
            await appState.addGoal(creation.newGoal!);
            goalId = creation.newGoal!.id;
          }
          for (final task in creation.tasks) {
            await appState.addTask(task.copyWith(goalId: goalId));
          }
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  String _taskSectionTitle(DateTime selectedDate) {
    final today = _dateOnly(DateTime.now());
    final diff = selectedDate.difference(today).inDays;
    if (diff == 0) return 'Today’s Tasks';
    if (diff == -1) return 'Yesterday’s Tasks';
    if (diff == 1) return 'Tomorrow’s Tasks';
    return '${_weekdayName(selectedDate.weekday)}’s Tasks';
  }

  static String _weekdayName(int weekday) {
    const names = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };
    return names[weekday] ?? 'Day';
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  Widget build(BuildContext context) {
    final appState = LevelUpScope.of(context);
    final tasks = appState.tasksForDate(_selectedDate);
    final completedCount = appState.completedTaskCountForDate(_selectedDate);
    final progress = appState.dailyProgressForDate(_selectedDate);
    final percent = (progress * 100).round();
    final name = appState.user.firstName.isEmpty
        ? 'there'
        : appState.user.firstName;
    final greeting = _greetingForNow(DateTime.now());
    final weeklyPercent = (appState.weeklyProgress * 100).round();
    final streak = appState.user.streakDays;
    final selectedAllDone = tasks.isNotEmpty && completedCount == tasks.length;

    return AppScrollView(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppHeader(),
              const SizedBox(height: 24),
              Text('$greeting, $name 👋', style: AppText.hero),
              const SizedBox(height: 10),
              Text(
                streak > 0
                    ? '$streak-day streak and counting —\nkeep the momentum'
                    : 'Your first step is ready —\nstart your momentum today',
                style: AppText.body,
              ),
              const SizedBox(height: 20),
              TodayGlassCard(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TODAY', style: AppText.eyebrow),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        RingProgress(
                          progress: progress,
                          label: '$percent%',
                          size: 106,
                          color: selectedAllDone
                              ? AppColors.sage
                              : AppColors.clay,
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$completedCount of ${tasks.length}',
                                style: AppText.metric,
                              ),
                              const Text('tasks done', style: AppText.taskDone),
                              const SizedBox(height: 8),
                              Text(
                                tasks.isEmpty
                                    ? 'Create a goal to unlock daily tasks'
                                    : completedCount == 0
                                    ? 'You can do this!'
                                    : 'You’re on fire 🔥 · Keep going',
                                style: AppText.caption.copyWith(
                                  color: completedCount > 0
                                      ? AppColors.clay
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        StatPill(
                          icon: CupertinoIcons.flame,
                          value: '$streak Day',
                          label: 'Streak',
                          color: AppColors.sage,
                        ),
                        const SizedBox(width: 16),
                        StatPill(
                          icon: CupertinoIcons.arrow_up_right,
                          value: '$weeklyPercent%',
                          label: 'weekly',
                          color: AppColors.gold,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              WeekStrip(
                selectedDate: _selectedDate,
                onOpenMonth: widget.onOpenMonth,
                onSelectDate: (date) =>
                    setState(() => _selectedDate = _dateOnly(date)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SectionHeader(
                      title: _taskSectionTitle(_selectedDate),
                      trailing: '$completedCount of ${tasks.length} done',
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(34, 34),
                    onPressed: () => _showAddTask(context),
                    child: const Icon(CupertinoIcons.add_circled, size: 24),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (tasks.isEmpty)
                const EmptyGlassState(
                  icon: CupertinoIcons.flag,
                  title: 'No tasks yet',
                  subtitle:
                      'Create your first goal and Lucy will prepare your first step.',
                )
              else
                for (final task in tasks) ...[
                  TaskCard(
                    icon: _taskIcon(task.category),
                    tag: task.completed ? 'DONE' : task.category,
                    title: task.title,
                    subtitle: task.subtitle,
                    done: task.completed,
                    onTap: () => _toggleTask(context, task),
                    onOpen: task.goalId == null
                        ? null
                        : () => widget.onOpenGoal(task.goalId!),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

class AddDailyTaskSheet extends StatefulWidget {
  const AddDailyTaskSheet({
    super.key,
    required this.goals,
    required this.initialDate,
    required this.onCreate,
  });

  final List<Goal> goals;
  final DateTime initialDate;
  final ValueChanged<DailyTaskCreation> onCreate;

  @override
  State<AddDailyTaskSheet> createState() => _AddDailyTaskSheetState();
}

class _AddDailyTaskSheetState extends State<AddDailyTaskSheet> {
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  final _newGoalTitle = TextEditingController();
  final _repeatTotal = TextEditingController(text: '1');
  String _selectedGoalId = 'new_goal';
  String _category = 'PERSONAL';
  late DateTime _plannedFor = widget.initialDate;
  bool _repeatsDaily = false;
  List<int> _repeatWeekdays = [];

  @override
  void initState() {
    super.initState();
    if (widget.goals.isNotEmpty) {
      _selectedGoalId = widget.goals.first.id;
      _category = widget.goals.first.category;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _newGoalTitle.dispose();
    _repeatTotal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedGoal = widget.goals.cast<Goal?>().firstWhere(
      (goal) => goal?.id == _selectedGoalId,
      orElse: () => null,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        28 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        borderRadius: 28,
        opacity: .92,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Add Daily Task', style: AppText.section),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(32, 32),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Icon(CupertinoIcons.xmark_circle_fill),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GoalFormField(label: 'Task title', controller: _title),
            const SizedBox(height: 12),
            GoalFormField(label: 'Task note', controller: _subtitle),
            const SizedBox(height: 14),
            const Text('Task date', style: AppText.eyebrow),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickTaskDate,
              child: _DateSelectorTile(
                icon: CupertinoIcons.calendar,
                label: _AddGoalSheetState._friendlyDate(_plannedFor),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: Text('Repeat', style: AppText.eyebrow)),
                SizedBox(
                  width: 96,
                  child: CupertinoTextField(
                    controller: _repeatTotal,
                    keyboardType: TextInputType.number,
                    placeholder: 'Times',
                    textAlign: TextAlign.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .46),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .66),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    icon: CupertinoIcons.repeat,
                    label: _repeatLabel,
                    onTap: _pickRepeatDays,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassActionButton(
                    icon: CupertinoIcons.calendar,
                    label: 'One-time',
                    onTap: () => setState(() {
                      _repeatsDaily = false;
                      _repeatWeekdays = [];
                      _repeatTotal.text = '1';
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Assign to goal', style: AppText.eyebrow),
            const SizedBox(height: 8),
            ChoiceWrap(
              values: [for (final goal in widget.goals) goal.id, 'new_goal'],
              selected: _selectedGoalId,
              labelFor: (value) => value == 'new_goal'
                  ? 'New goal'
                  : widget.goals.firstWhere((goal) => goal.id == value).title,
              onSelected: (value) {
                setState(() {
                  _selectedGoalId = value;
                  if (value != 'new_goal') {
                    _category = widget.goals
                        .firstWhere((goal) => goal.id == value)
                        .category;
                  }
                });
              },
            ),
            if (_selectedGoalId == 'new_goal') ...[
              const SizedBox(height: 12),
              GoalFormField(label: 'New goal name', controller: _newGoalTitle),
              const SizedBox(height: 14),
              const Text('Life Area', style: AppText.eyebrow),
              const SizedBox(height: 8),
              ChoiceWrap(
                values: const [
                  'RELATIONSHIPS',
                  'HEALTH',
                  'FINANCE',
                  'PERSONAL',
                  'CAREER',
                ],
                selected: _category,
                onSelected: (value) => setState(() => _category = value),
              ),
            ],
            const SizedBox(height: 18),
            GlassActionButton(
              icon: CupertinoIcons.check_mark_circled,
              label: 'Add task',
              strong: true,
              onTap: () {
                final now = DateTime.now();
                final taskTitle = _title.text.trim().isEmpty
                    ? 'New daily task'
                    : _title.text.trim();
                final repeatTotal =
                    int.tryParse(_repeatTotal.text.trim())?.clamp(1, 365) ?? 1;
                final repeatDays =
                    _repeatsDaily
                          ? const [1, 2, 3, 4, 5, 6, 7]
                          : [..._repeatWeekdays]
                      ..sort();
                final scheduledDates = _scheduledTaskDates(
                  start: _plannedFor,
                  repeatTotal: repeatTotal,
                  repeatDays: repeatDays,
                );
                final repeatGroupId = scheduledDates.length > 1
                    ? 'repeat_${now.millisecondsSinceEpoch}'
                    : null;
                Goal? newGoal;
                if (_selectedGoalId == 'new_goal') {
                  final goalId = 'goal_${now.millisecondsSinceEpoch}';
                  newGoal = Goal(
                    id: goalId,
                    category: _category,
                    title: _newGoalTitle.text.trim().isEmpty
                        ? taskTitle
                        : _newGoalTitle.text.trim(),
                    detail: 'Created from Home',
                    progress: 0,
                    vision: 'New vision',
                    timeline: taskTitle,
                    completed: false,
                    milestones: [
                      Milestone(
                        id: '${goalId}_milestone_0',
                        title: taskTitle,
                        dueDate: _repeatsDaily || _repeatWeekdays.isNotEmpty
                            ? null
                            : _plannedFor,
                        repeatsDaily: _repeatsDaily,
                        repeatWeekdays: _repeatWeekdays,
                      ),
                    ],
                  );
                }
                widget.onCreate(
                  DailyTaskCreation(
                    tasks: [
                      for (var i = 0; i < scheduledDates.length; i++)
                        DailyTask(
                          id: 'task_${now.millisecondsSinceEpoch}_$i',
                          title: taskTitle,
                          subtitle: _subtitle.text.trim().isEmpty
                              ? _taskScheduleSubtitle(
                                  scheduledDates.length,
                                  i + 1,
                                )
                              : _subtitle.text.trim(),
                          category: selectedGoal?.category ?? _category,
                          completed: false,
                          plannedFor: scheduledDates[i],
                          dueDate: scheduledDates[i],
                          repeatGroupId: repeatGroupId,
                          repeatIndex: i + 1,
                          repeatTotal: scheduledDates.length,
                          repeatWeekdays: repeatDays,
                        ),
                    ],
                    goalId: _selectedGoalId == 'new_goal'
                        ? null
                        : _selectedGoalId,
                    newGoal: newGoal,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String get _repeatLabel {
    if (_repeatsDaily) return 'Every day';
    if (_repeatWeekdays.isNotEmpty) {
      return _MilestoneDraft._weekdayLabel(_repeatWeekdays);
    }
    return 'Choose days';
  }

  Future<void> _pickTaskDate() async {
    final selected = await _showDatePicker(_plannedFor);
    if (selected != null) setState(() => _plannedFor = selected);
  }

  Future<DateTime?> _showDatePicker(DateTime initialDate) {
    var selected = initialDate;
    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (context) => Container(
        height: 330,
        padding: const EdgeInsets.only(top: 8),
        color: AppColors.cream,
        child: Column(
          children: [
            Row(
              children: [
                CupertinoButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                CupertinoButton(
                  child: const Text('Done'),
                  onPressed: () => Navigator.of(context).pop(selected),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: initialDate,
                minimumYear: 2024,
                maximumYear: 2035,
                onDateTimeChanged: (date) => selected = date,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRepeatDays() {
    final selected = _repeatsDaily
        ? {1, 2, 3, 4, 5, 6, 7}
        : _repeatWeekdays.toSet();
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setPickerState) {
          void toggleDay(int day) {
            setPickerState(() {
              if (selected.contains(day)) {
                selected.remove(day);
              } else {
                selected.add(day);
              }
            });
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              borderRadius: 28,
              opacity: .94,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Repeat days', style: AppText.section),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(32, 32),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Icon(CupertinoIcons.xmark_circle_fill),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final day in const [
                        (1, 'Mon'),
                        (2, 'Tue'),
                        (3, 'Wed'),
                        (4, 'Thu'),
                        (5, 'Fri'),
                        (6, 'Sat'),
                        (7, 'Sun'),
                      ])
                        GestureDetector(
                          onTap: () => toggleDay(day.$1),
                          child: CategoryPill(
                            label: day.$2,
                            active: selected.contains(day.$1),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: GlassActionButton(
                          icon: CupertinoIcons.calendar,
                          label: 'One-time',
                          onTap: () {
                            setState(() {
                              _repeatsDaily = false;
                              _repeatWeekdays = [];
                              _repeatTotal.text = '1';
                            });
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GlassActionButton(
                          icon: CupertinoIcons.check_mark_circled,
                          label: 'Save',
                          strong: true,
                          onTap: () {
                            setState(() {
                              final days = selected.toList()..sort();
                              _repeatsDaily = days.length == 7;
                              _repeatWeekdays = _repeatsDaily ? [] : days;
                              if (days.isNotEmpty &&
                                  (int.tryParse(_repeatTotal.text) ?? 1) <= 1) {
                                _repeatTotal.text = '10';
                              }
                            });
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<DateTime> _scheduledTaskDates({
    required DateTime start,
    required int repeatTotal,
    required List<int> repeatDays,
  }) {
    final startDate = DateTime(start.year, start.month, start.day);
    if (repeatDays.isEmpty || repeatTotal <= 1) return [startDate];

    final dates = <DateTime>[];
    var cursor = startDate;
    while (dates.length < repeatTotal) {
      if (repeatDays.contains(cursor.weekday)) dates.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return dates;
  }

  String _taskScheduleSubtitle(int total, int index) {
    if (total <= 1) return 'Today’s action';
    return 'Repeated task $index of $total';
  }
}

class DailyTaskCreation {
  const DailyTaskCreation({required this.tasks, this.goalId, this.newGoal});

  final List<DailyTask> tasks;
  final String? goalId;
  final Goal? newGoal;
}

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({
    super.key,
    required this.onOpenGoal,
    required this.resetToken,
  });

  final ValueChanged<String> onOpenGoal;
  final int resetToken;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  bool _completed = false;
  String _activeFilter = 'All';

  @override
  void didUpdateWidget(covariant GoalsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      _completed = false;
      _activeFilter = 'All';
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = LevelUpScope.of(context);
    final activeGoals = appState.activeGoals;
    final completedGoals = appState.completedGoals;
    final filteredActiveGoals = _filterGoals(activeGoals, _activeFilter);
    const goalsContentOverlap = -24.0;

    return AppScrollView(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppHeader(),
              const SizedBox(height: 30),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your Goals', style: AppText.title),
                        const SizedBox(height: 8),
                        Text(
                          'Level up. Day by day.',
                          style: AppText.body.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  const GoalsHeaderImage(),
                ],
              ),
              Transform.translate(
                offset: const Offset(0, goalsContentOverlap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassSegmentedControl(
                      selectedRight: _completed,
                      leftTitle: '${activeGoals.length}',
                      leftLabel: 'Active Goals',
                      rightTitle: '${completedGoals.length}',
                      rightLabel: 'Completed',
                      onChanged: (value) => setState(() => _completed = value),
                    ),
                    const SizedBox(height: 18),
                    if (_completed) ...[
                      CompletedGoalsContent(
                        completedGoals: completedGoals,
                        onOpenGoal: widget.onOpenGoal,
                      ),
                    ] else ...[
                      GlassActionButton(
                        icon: CupertinoIcons.plus_circle,
                        label: 'Add new goal',
                        strong: false,
                        onTap: _showAddGoal,
                      ),
                      const SizedBox(height: 18),
                      _GoalAreaFilters(
                        selectedFilter: _activeFilter,
                        onSelected: (filter) =>
                            setState(() => _activeFilter = filter),
                      ),
                      const SizedBox(height: 18),
                      if (activeGoals.isEmpty)
                        const EmptyGlassState(
                          icon: CupertinoIcons.flag,
                          title: 'No active goals yet',
                          subtitle:
                              'Create a goal to turn your future vision into clear steps.',
                        )
                      else if (filteredActiveGoals.isEmpty)
                        EmptyGlassState(
                          icon:
                              CupertinoIcons.line_horizontal_3_decrease_circle,
                          title: 'No active $_activeFilter goals',
                          subtitle: 'Try another life area.',
                        )
                      else
                        for (final goal in filteredActiveGoals) ...[
                          GoalCard(
                            goal: goal,
                            currentTask: _currentTaskTitle(appState, goal),
                            onTap: () => widget.onOpenGoal(goal.id),
                            onStart: goal.status == GoalStatus.notStarted
                                ? () => _startGoal(goal)
                                : null,
                            onTaskTap: goal.status == GoalStatus.currentTask
                                ? () => widget.onOpenGoal(goal.id)
                                : null,
                            onMore: () => _showGoalActions(goal),
                          ),
                          const SizedBox(height: 14),
                        ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Goal> _filterGoals(List<Goal> goals, String filter) {
    if (filter == 'All') return goals;
    return goals
        .where((goal) => goal.category.toUpperCase() == filter.toUpperCase())
        .toList();
  }

  void _showAddGoal() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => AddGoalSheet(
        onCreate: (goal) async {
          await LevelUpScope.read(context).addGoal(goal);
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }

  String _currentTaskTitle(LevelUpAppState appState, Goal goal) {
    final task = appState.tasks.cast<DailyTask?>().firstWhere(
      (item) => item != null && item.goalId == goal.id && !item.completed,
      orElse: () => null,
    );
    if (task != null) return task.title;

    final milestone = goal.milestones.cast<Milestone?>().firstWhere(
      (item) => item != null && !item.completed,
      orElse: () => null,
    );
    return milestone?.title ?? 'Every task is complete';
  }

  Future<void> _startGoal(Goal goal) async {
    await LevelUpScope.read(context).startGoal(goal.id);
  }

  void _showGoalActions(Goal goal) {
    final pausedLabel = goal.paused ? 'Resume goal' : 'Pause goal';
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(goal.title),
        message: Text(goal.category),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _showEditGoal(goal);
            },
            child: const Text('Edit goal'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              await LevelUpScope.read(
                context,
              ).setGoalPaused(goal.id, !goal.paused);
            },
            child: Text(pausedLabel),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              await LevelUpScope.read(context).completeGoal(goal.id);
            },
            child: const Text('Mark as completed'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _confirmDelete(goal);
            },
            child: const Text('Delete goal'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showEditGoal(Goal goal) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => AddGoalSheet(
        initialGoal: goal,
        title: 'Edit Goal',
        submitLabel: 'Save changes',
        onCreate: (updatedGoal) async {
          await LevelUpScope.read(context).updateGoal(updatedGoal);
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }

  void _confirmDelete(Goal goal) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Delete goal?'),
        content: Text('This will remove "${goal.title}" and its linked tasks.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await LevelUpScope.read(context).deleteGoal(goal.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class CompletedGoalsContent extends StatefulWidget {
  const CompletedGoalsContent({
    super.key,
    required this.completedGoals,
    required this.onOpenGoal,
  });

  final List<Goal> completedGoals;
  final ValueChanged<String> onOpenGoal;

  @override
  State<CompletedGoalsContent> createState() => _CompletedGoalsContentState();
}

class _CompletedGoalsContentState extends State<CompletedGoalsContent> {
  String _selectedFilter = 'All';

  List<Goal> get _filteredGoals {
    if (_selectedFilter == 'All') return widget.completedGoals;
    return widget.completedGoals
        .where(
          (goal) =>
              goal.category.toUpperCase() == _selectedFilter.toUpperCase(),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredGoals = _filteredGoals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.completedGoals.isNotEmpty) ...[
          _CompletedGoalsHero(completedCount: widget.completedGoals.length),
          const SizedBox(height: 18),
        ],
        _GoalAreaFilters(
          selectedFilter: _selectedFilter,
          onSelected: (filter) => setState(() => _selectedFilter = filter),
        ),
        const SizedBox(height: 18),
        if (widget.completedGoals.isEmpty)
          const EmptyGlassState(
            icon: CupertinoIcons.rosette,
            title: 'No completed goals yet',
            subtitle: 'Completed goals will appear here.',
          )
        else if (filteredGoals.isEmpty)
          EmptyGlassState(
            icon: CupertinoIcons.line_horizontal_3_decrease_circle,
            title: 'No completed $_selectedFilter goals',
            subtitle: 'Try another life area.',
          )
        else
          for (final goal in filteredGoals) ...[
            CompletedGoalRow(
              icon: _goalIcon(goal.category),
              title: goal.title,
              area: _formatCategory(goal.category),
              date: _formatGoalDate(goal),
              onTap: () => widget.onOpenGoal(goal.id),
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 8),
      ],
    );
  }

  IconData _goalIcon(String category) {
    switch (category.toUpperCase()) {
      case 'CAREER':
        return CupertinoIcons.briefcase;
      case 'FINANCE':
        return CupertinoIcons.money_dollar;
      case 'LEARNING':
        return CupertinoIcons.book;
      case 'RELATIONSHIPS':
      case 'FAMILY':
        return CupertinoIcons.person_2;
      case 'HEALTH':
        return Icons.fitness_center;
      default:
        return CupertinoIcons.sparkles;
    }
  }

  String _formatGoalDate(Goal goal) {
    final date = goal.completedAt ?? goal.startedAt;
    if (date == null) return 'Completed';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return 'Completed on ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatCategory(String category) {
    if (category.isEmpty) return 'Personal';
    final lower = category.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }
}

class _GoalAreaFilters extends StatelessWidget {
  const _GoalAreaFilters({
    required this.selectedFilter,
    required this.onSelected,
  });

  static const filters = ['All', 'Health', 'Career', 'Personal', 'Finance'];

  final String selectedFilter;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final filter in filters) ...[
            GestureDetector(
              onTap: () => onSelected(filter),
              child: _CompletedFilterPill(
                label: filter,
                active: selectedFilter == filter,
              ),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _CompletedGoalsHero extends StatelessWidget {
  const _CompletedGoalsHero({required this.completedCount});

  final int completedCount;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(22, 22, 18, 18),
      borderRadius: 24,
      opacity: .54,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trophyWidth = (constraints.maxWidth * .34).clamp(104.0, 148.0);

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amazing work!\nYou’ve completed $completedCount ${completedCount == 1 ? 'goal' : 'goals'}',
                      style: AppText.section.copyWith(
                        fontSize: 22,
                        height: 1.16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Every goal completed is a step toward your best future self.',
                      style: AppText.body.copyWith(
                        color: AppColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Image.asset(
                'assets/images/completed_goals_trophy.png',
                width: trophyWidth,
                height: trophyWidth * 1.2,
                fit: BoxFit.contain,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CompletedFilterPill extends StatelessWidget {
  const _CompletedFilterPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: .5)
            : AppColors.cream.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? AppColors.sage.withValues(alpha: .62)
              : Colors.white.withValues(alpha: .6),
        ),
      ),
      child: Text(
        label,
        style: AppText.tiny.copyWith(
          color: active ? AppColors.sage : AppColors.muted,
          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}

class CompletedGoalRow extends StatelessWidget {
  const CompletedGoalRow({
    super.key,
    required this.icon,
    required this.title,
    required this.area,
    required this.date,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String area;
  final String date;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        borderRadius: 22,
        opacity: .56,
        child: Row(
          children: [
            SoftIconBubble(icon: icon, color: AppColors.sage, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.section.copyWith(fontSize: 18)),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.sage,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        area,
                        style: AppText.tiny.copyWith(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    date,
                    style: AppText.tiny.copyWith(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.sage, width: 1.5),
                color: Colors.white.withValues(alpha: .55),
              ),
              child: const Icon(
                CupertinoIcons.check_mark,
                size: 18,
                color: AppColors.sage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GoalsOverviewCard extends StatelessWidget {
  const GoalsOverviewCard({
    super.key,
    required this.progress,
    required this.activeCount,
  });

  final double progress;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      borderRadius: 28,
      opacity: .50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GOALS', style: AppText.eyebrow),
          const SizedBox(height: 16),
          Wrap(
            spacing: 18,
            runSpacing: 16,
            children: const [
              GoalCategoryMetric(
                icon: Icons.fitness_center,
                value: '62%',
                label: 'Health',
                color: AppColors.sage,
              ),
              GoalCategoryMetric(
                icon: CupertinoIcons.briefcase,
                value: '38%',
                label: 'Career',
                color: AppColors.gold,
              ),
              GoalCategoryMetric(
                icon: CupertinoIcons.money_dollar,
                value: '24%',
                label: 'Finance',
                color: AppColors.sage,
              ),
              GoalCategoryMetric(
                icon: CupertinoIcons.heart,
                value: '44%',
                label: 'Personal',
                color: AppColors.sage,
              ),
              GoalCategoryMetric(
                icon: CupertinoIcons.person_2,
                value: '51%',
                label: 'Relationships',
                color: AppColors.sage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CompletedGoalsSummaryCard extends StatelessWidget {
  const CompletedGoalsSummaryCard({super.key, required this.completedGoals});

  final List<GoalData> completedGoals;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      borderRadius: 28,
      opacity: .50,
      child: Row(
        children: [
          RingProgress(
            progress: 1,
            label: '${completedGoals.length}',
            size: 112,
            color: AppColors.sage,
            labelStyle: AppText.metric,
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You’ve achieved so much!',
                  style: AppText.section.copyWith(color: AppColors.sage),
                ),
                const SizedBox(height: 7),
                Text(
                  'Keep building your future self.',
                  style: AppText.body.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: const [
                    Expanded(
                      child: SmallStat(
                        icon: CupertinoIcons.flag,
                        value: '12',
                        label: 'Goals',
                      ),
                    ),
                    Expanded(
                      child: SmallStat(
                        icon: CupertinoIcons.calendar,
                        value: '256',
                        label: 'Days',
                      ),
                    ),
                    Expanded(
                      child: SmallStat(
                        icon: CupertinoIcons.rosette,
                        value: '8',
                        label: 'Wins',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GoalStatsStrip extends StatelessWidget {
  const GoalStatsStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      borderRadius: 22,
      opacity: .42,
      child: Row(
        children: const [
          Expanded(
            child: SmallStat(
              icon: CupertinoIcons.flame_fill,
              value: '4 Day',
              label: 'Streak',
            ),
          ),
          SizedBox(
            height: 42,
            child: VerticalDivider(color: AppColors.hairline),
          ),
          Expanded(
            child: SmallStat(
              icon: CupertinoIcons.arrow_up_right,
              value: '87%',
              label: 'Weekly',
            ),
          ),
          SizedBox(
            height: 42,
            child: VerticalDivider(color: AppColors.hairline),
          ),
          Expanded(
            child: SmallStat(
              icon: CupertinoIcons.scope,
              value: '3',
              label: 'Active',
            ),
          ),
        ],
      ),
    );
  }
}

class GoalCategoryMetric extends StatelessWidget {
  const GoalCategoryMetric({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SoftIconBubble(icon: icon, color: color),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AppText.bodyStrong),
            const SizedBox(height: 2),
            Text(label, style: AppText.caption),
          ],
        ),
      ],
    );
  }
}

class SmallStat extends StatelessWidget {
  const SmallStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SoftIconBubble(icon: icon, color: AppColors.sage, size: 42),
        const SizedBox(height: 7),
        Text(
          value,
          style: AppText.bodyStrong,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: AppText.tiny.copyWith(color: AppColors.muted),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class SoftIconBubble extends StatelessWidget {
  const SoftIconBubble({
    super.key,
    required this.icon,
    required this.color,
    this.size = 46,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: .55),
        border: Border.all(color: Colors.white.withValues(alpha: .75)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size * .45),
    );
  }
}

class GoalStaircaseIllustration extends StatelessWidget {
  const GoalStaircaseIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return const MountainPathImage(height: 126);
  }
}

class GoalsHeaderImage extends StatelessWidget {
  const GoalsHeaderImage({super.key});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(-10, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.asset(
          'assets/images/goal_staircase_transparent_crop.png',
          width: 124,
          height: 124,
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
    );
  }
}

class MountainPathImage extends StatelessWidget {
  const MountainPathImage({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.asset(
        'assets/images/goal_staircase_transparent_crop.png',
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        alignment: const Alignment(-0.2, -0.4),
      ),
    );
  }
}

class GoalStaircasePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stepPaint = Paint()..color = AppColors.cream.withValues(alpha: .92);
    final sagePaint = Paint()..color = AppColors.sage.withValues(alpha: .28);
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: .05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    const count = 5;
    final stepW = size.width * .28;
    final stepH = size.height * .12;
    final baseY = size.height * .84;
    final startX = size.width * .08;
    for (var i = 0; i < count; i++) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          startX + i * stepW * .52,
          baseY - i * stepH * 1.15,
          stepW,
          stepH,
        ),
        const Radius.circular(7),
      );
      canvas.drawRRect(rect.shift(const Offset(0, 5)), shadowPaint);
      canvas.drawRRect(rect, stepPaint);
      if (i < 3) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              rect.left + rect.width * .35,
              rect.top,
              rect.width * .30,
              rect.height,
            ),
            const Radius.circular(5),
          ),
          sagePaint,
        );
      }
    }

    final figure = Paint()
      ..color = AppColors.sage
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final p = Offset(size.width * .38, size.height * .50);
    canvas.drawCircle(Offset(p.dx, p.dy - 20), 7, figure);
    canvas.drawLine(
      Offset(p.dx, p.dy - 12),
      Offset(p.dx - 4, p.dy + 15),
      figure,
    );
    canvas.drawLine(
      Offset(p.dx - 2, p.dy),
      Offset(p.dx - 17, p.dy + 9),
      figure,
    );
    canvas.drawLine(
      Offset(p.dx - 3, p.dy + 14),
      Offset(p.dx - 17, p.dy + 32),
      figure,
    );
    canvas.drawLine(
      Offset(p.dx - 3, p.dy + 14),
      Offset(p.dx + 17, p.dy + 24),
      figure,
    );

    final flagPole = Paint()
      ..color = AppColors.sage
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final flagBase = Offset(size.width * .78, size.height * .16);
    canvas.drawLine(flagBase, Offset(flagBase.dx, flagBase.dy + 38), flagPole);
    final path = Path()
      ..moveTo(flagBase.dx, flagBase.dy + 2)
      ..lineTo(flagBase.dx + 26, flagBase.dy + 8)
      ..lineTo(flagBase.dx, flagBase.dy + 16)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.sage);

    final plantPaint = Paint()..color = AppColors.sage.withValues(alpha: .46);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .14, size.height * .78),
        width: 9,
        height: 24,
      ),
      plantPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .08, size.height * .82),
        width: 8,
        height: 18,
      ),
      plantPaint,
    );
  }

  @override
  bool shouldRepaint(covariant GoalStaircasePainter oldDelegate) => false;
}

class AchievementIllustration extends StatelessWidget {
  const AchievementIllustration({
    super.key,
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.sage.withValues(alpha: .08),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const GoalStaircaseIllustration(),
          Positioned(
            right: 10,
            bottom: 10,
            child: SoftIconBubble(icon: icon, color: color, size: 34),
          ),
        ],
      ),
    );
  }
}

class AddGoalSheet extends StatefulWidget {
  const AddGoalSheet({
    super.key,
    required this.onCreate,
    this.initialGoal,
    this.title = 'Add New Goal',
    this.submitLabel = 'Create goal',
  });

  final ValueChanged<Goal> onCreate;
  final Goal? initialGoal;
  final String title;
  final String submitLabel;

  @override
  State<AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends State<AddGoalSheet> {
  late final _title = TextEditingController(
    text: widget.initialGoal?.title ?? '',
  );
  late DateTime _deadline = _initialDeadline(widget.initialGoal);
  late final List<_MilestoneDraft> _milestones = _initialMilestones(
    widget.initialGoal,
  );
  String _area = 'HEALTH';
  String _vision = '';
  bool _aiPlanning = false;

  @override
  void initState() {
    super.initState();
    final goal = widget.initialGoal;
    if (goal != null) {
      _area = goal.category;
      _vision = goal.vision;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final milestone in _milestones) {
      milestone.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, topInset + 18, 18, 24 + keyboard),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        borderRadius: 28,
        opacity: .9,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.of(context).size.height - topInset - keyboard - 64,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(widget.title, style: AppText.section)),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 32),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                GoalFormField(label: 'Goal name', controller: _title),
                const SizedBox(height: 12),
                const Text('Deadline', style: AppText.eyebrow),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickDeadline,
                  child: _DateSelectorTile(
                    icon: CupertinoIcons.calendar,
                    label: _friendlyDate(_deadline),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Life Area', style: AppText.eyebrow),
                const SizedBox(height: 8),
                ChoiceWrap(
                  values: const [
                    'RELATIONSHIPS',
                    'HEALTH',
                    'FINANCE',
                    'PERSONAL',
                    'CAREER',
                  ],
                  selected: _area,
                  onSelected: (value) => setState(() => _area = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Task plan', style: AppText.eyebrow),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      onPressed: _aiPlanning ? null : _generateAiPlan,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.sparkles, size: 16),
                          const SizedBox(width: 5),
                          Text(_aiPlanning ? 'Drafting' : 'AI plan'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      onPressed: _addMilestone,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.add_circled, size: 16),
                          SizedBox(width: 5),
                          Text('Add Task'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _milestones.length; i++) ...[
                  _MilestoneEditorRow(
                    index: i + 1,
                    milestone: _milestones[i],
                    onEditTitle: () => _editMilestoneTitle(i),
                    onPickDate: () => _pickMilestoneDate(i),
                    onPickWeekdays: () => _pickMilestoneWeekdays(i),
                    onDelete: _milestones.length <= 1
                        ? null
                        : () => _deleteMilestone(i),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 18),
                GlassActionButton(
                  icon: CupertinoIcons.check_mark_circled,
                  label: widget.submitLabel,
                  strong: true,
                  onTap: () {
                    final existing = widget.initialGoal;
                    final currentVision = LevelUpScope.read(
                      context,
                    ).user.vision.trim();
                    final goalTitle = _title.text.trim();
                    final id =
                        existing?.id ??
                        'goal_${DateTime.now().millisecondsSinceEpoch}';
                    final milestones = _milestones.asMap().entries.map((entry) {
                      final draft = entry.value;
                      return Milestone(
                        id:
                            existing != null &&
                                entry.key < existing.milestones.length
                            ? existing.milestones[entry.key].id
                            : '${id}_milestone_${entry.key}',
                        title: draft.title.text.trim().isEmpty
                            ? 'Task ${entry.key + 1}'
                            : draft.title.text.trim(),
                        subtitle: draft.scheduleLabel,
                        completed:
                            existing != null &&
                            entry.key < existing.milestones.length &&
                            existing.milestones[entry.key].completed,
                        dueDate: draft.repeatsDaily ? null : draft.dueDate,
                        repeatsDaily: draft.repeatsDaily,
                        repeatWeekdays: draft.repeatWeekdays,
                      );
                    }).toList();
                    widget.onCreate(
                      Goal(
                        id: id,
                        category: _area,
                        title: goalTitle.isEmpty ? 'New Goal' : goalTitle,
                        detail: _friendlyDate(_deadline),
                        progress: existing?.progress ?? 0,
                        vision: _vision.trim().isNotEmpty
                            ? _vision.trim()
                            : currentVision.isNotEmpty
                            ? currentVision
                            : (goalTitle.isEmpty ? 'My vision' : goalTitle),
                        timeline: milestones
                            .map((milestone) => milestone.title)
                            .join(' → '),
                        completed: existing?.completed ?? false,
                        milestones: milestones.isEmpty
                            ? [
                                Milestone(
                                  id: '${id}_milestone_0',
                                  title: 'Start with one clear task',
                                ),
                              ]
                            : milestones,
                        startedAt: existing?.startedAt,
                        completedAt: existing?.completedAt,
                        paused: existing?.paused ?? false,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addMilestone() {
    setState(() {
      _milestones.add(_MilestoneDraft(title: ''));
    });
  }

  void _deleteMilestone(int index) {
    final removed = _milestones.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _generateAiPlan() async {
    final options = await _showAiPlanOptions();
    if (options == null) return;

    setState(() => _aiPlanning = true);
    final result = await AiService.instance.generateTaskPlan(
      AiTaskPlanRequest(
        goalTitle: _title.text.trim().isEmpty ? 'My goal' : _title.text.trim(),
        category: _area,
        deadline: _deadline,
        daysPerWeek: options.daysPerWeek,
        minutesPerSession: options.minutesPerSession,
        preferredWeekdays: options.weekdays,
      ),
    );
    if (!mounted) return;

    setState(() {
      for (final milestone in _milestones) {
        milestone.dispose();
      }
      _milestones
        ..clear()
        ..addAll(
          result.tasks.map(
            (task) => _MilestoneDraft(
              title: task.title,
              dueDate: task.dueDate,
              repeatsDaily: task.repeatsDaily,
              repeatWeekdays: task.repeatWeekdays,
            ),
          ),
        );
      _aiPlanning = false;
    });

    await _showInfoDialog('AI task plan', result.note);
  }

  Future<({int daysPerWeek, int minutesPerSession, List<int> weekdays})?>
  _showAiPlanOptions() {
    var daysPerWeek = 3;
    var minutesPerSession = 30;
    final weekdays = <int>{1, 3, 5};
    return showCupertinoModalPopup<
      ({int daysPerWeek, int minutesPerSession, List<int> weekdays})
    >(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void toggleWeekday(int day) {
            setSheetState(() {
              if (weekdays.contains(day)) {
                weekdays.remove(day);
              } else {
                weekdays.add(day);
              }
              daysPerWeek = weekdays.length.clamp(1, 7);
            });
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              borderRadius: 28,
              opacity: .94,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('AI task plan', style: AppText.section),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(32, 32),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Icon(CupertinoIcons.xmark_circle_fill),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Lucy will draft tasks. You can edit everything before saving.',
                    style: AppText.caption,
                  ),
                  const SizedBox(height: 16),
                  const Text('Days per week', style: AppText.eyebrow),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in const [1, 2, 3, 4, 5, 6, 7])
                        GestureDetector(
                          onTap: () => setSheetState(() {
                            daysPerWeek = value;
                            weekdays
                              ..clear()
                              ..addAll(_defaultWeekdays(value));
                          }),
                          child: CategoryPill(
                            label: '$value',
                            active: daysPerWeek == value,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Preferred days', style: AppText.eyebrow),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final day in const [
                        (1, 'Mon'),
                        (2, 'Tue'),
                        (3, 'Wed'),
                        (4, 'Thu'),
                        (5, 'Fri'),
                        (6, 'Sat'),
                        (7, 'Sun'),
                      ])
                        GestureDetector(
                          onTap: () => toggleWeekday(day.$1),
                          child: CategoryPill(
                            label: day.$2,
                            active: weekdays.contains(day.$1),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Time per session', style: AppText.eyebrow),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in const [15, 30, 45, 60])
                        GestureDetector(
                          onTap: () =>
                              setSheetState(() => minutesPerSession = value),
                          child: CategoryPill(
                            label: '$value min',
                            active: minutesPerSession == value,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  GlassActionButton(
                    icon: CupertinoIcons.sparkles,
                    label: 'Generate draft',
                    strong: true,
                    onTap: () {
                      final selectedWeekdays = weekdays.toList()..sort();
                      Navigator.of(context).pop((
                        daysPerWeek: daysPerWeek,
                        minutesPerSession: minutesPerSession,
                        weekdays: selectedWeekdays,
                      ));
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<int> _defaultWeekdays(int daysPerWeek) {
    const patterns = {
      1: [1],
      2: [1, 4],
      3: [1, 3, 5],
      4: [1, 2, 4, 6],
      5: [1, 2, 3, 4, 5],
      6: [1, 2, 3, 4, 5, 6],
      7: [1, 2, 3, 4, 5, 6, 7],
    };
    return patterns[daysPerWeek] ?? const [1, 3, 5];
  }

  Future<void> _showInfoDialog(String title, String message) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _editMilestoneTitle(int index) async {
    final draft = _milestones[index];
    final controller = TextEditingController(text: draft.title.text);
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Edit task'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: appTextInputFormatters,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              setState(() => draft.title.text = controller.text.trim());
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _pickDeadline() async {
    final selected = await _showDatePicker(_deadline);
    if (selected != null) setState(() => _deadline = selected);
  }

  Future<void> _pickMilestoneDate(int index) async {
    final draft = _milestones[index];
    final selected = await _showDatePicker(draft.dueDate ?? _deadline);
    if (selected != null) {
      setState(() {
        draft.dueDate = selected;
        draft.repeatsDaily = false;
        draft.repeatWeekdays = [];
      });
    }
  }

  Future<void> _pickMilestoneWeekdays(int index) {
    final draft = _milestones[index];
    final selected = draft.repeatsDaily
        ? {1, 2, 3, 4, 5, 6, 7}
        : draft.repeatWeekdays.toSet();
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setPickerState) {
          void toggleDay(int day) {
            setPickerState(() {
              if (selected.contains(day)) {
                selected.remove(day);
              } else {
                selected.add(day);
              }
            });
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              borderRadius: 28,
              opacity: .94,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Repeat days', style: AppText.section),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(32, 32),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Icon(CupertinoIcons.xmark_circle_fill),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final day in const [
                        (1, 'Mon'),
                        (2, 'Tue'),
                        (3, 'Wed'),
                        (4, 'Thu'),
                        (5, 'Fri'),
                        (6, 'Sat'),
                        (7, 'Sun'),
                      ])
                        GestureDetector(
                          onTap: () => toggleDay(day.$1),
                          child: CategoryPill(
                            label: day.$2,
                            active: selected.contains(day.$1),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: GlassActionButton(
                          icon: CupertinoIcons.calendar,
                          label: 'One-time',
                          onTap: () {
                            setState(() {
                              draft.repeatsDaily = false;
                              draft.repeatWeekdays = [];
                            });
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GlassActionButton(
                          icon: CupertinoIcons.check_mark_circled,
                          label: 'Save',
                          strong: true,
                          onTap: () {
                            setState(() {
                              final days = selected.toList()..sort();
                              draft.repeatsDaily = days.length == 7;
                              draft.repeatWeekdays = draft.repeatsDaily
                                  ? []
                                  : days;
                              if (days.isNotEmpty) draft.dueDate = null;
                            });
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<DateTime?> _showDatePicker(DateTime initialDate) {
    var selected = initialDate;
    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (context) => Container(
        height: 330,
        padding: const EdgeInsets.only(top: 8),
        color: AppColors.cream,
        child: Column(
          children: [
            Row(
              children: [
                CupertinoButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                CupertinoButton(
                  child: const Text('Done'),
                  onPressed: () => Navigator.of(context).pop(selected),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: initialDate,
                minimumYear: 2024,
                maximumYear: 2035,
                onDateTimeChanged: (date) => selected = date,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static DateTime _initialDeadline(Goal? goal) {
    if (goal == null) return DateTime.now().add(const Duration(days: 90));
    return _parseGoalDate(goal.detail) ??
        goal.milestones
            .cast<Milestone?>()
            .firstWhere(
              (milestone) => milestone?.dueDate != null,
              orElse: () => null,
            )
            ?.dueDate ??
        DateTime.now().add(const Duration(days: 90));
  }

  static DateTime? _parseGoalDate(String value) {
    final iso = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
    if (iso != null) return DateTime.tryParse(iso.group(0)!);
    return null;
  }

  static List<_MilestoneDraft> _initialMilestones(Goal? goal) {
    if (goal == null || goal.milestones.isEmpty) {
      return [_MilestoneDraft(title: '')];
    }

    return [
      for (final milestone in goal.milestones)
        _MilestoneDraft(
          title: milestone.title,
          dueDate: milestone.dueDate,
          repeatsDaily: milestone.repeatsDaily,
          repeatWeekdays: milestone.repeatWeekdays,
        ),
    ];
  }

  static String _friendlyDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _MilestoneDraft {
  _MilestoneDraft({
    required String title,
    this.dueDate,
    this.repeatsDaily = false,
    List<int> repeatWeekdays = const [],
  }) : repeatWeekdays = [...repeatWeekdays],
       title = TextEditingController(text: title);

  final TextEditingController title;
  DateTime? dueDate;
  bool repeatsDaily;
  List<int> repeatWeekdays;

  String get scheduleLabel {
    if (repeatsDaily) return 'Every day';
    if (repeatWeekdays.isNotEmpty) return _weekdayLabel(repeatWeekdays);
    if (dueDate == null) return 'No date';
    return _AddGoalSheetState._friendlyDate(dueDate!);
  }

  static String _weekdayLabel(List<int> days) {
    const labels = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    final sorted = [...days]..sort();
    return sorted.map((day) => labels[day]).whereType<String>().join(', ');
  }

  void dispose() => title.dispose();
}

class _DateSelectorTile extends StatelessWidget {
  const _DateSelectorTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: .72)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.sage),
          const SizedBox(width: 9),
          Expanded(child: Text(label, style: AppText.bodyStrong)),
          const Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}

class _MilestoneEditorRow extends StatelessWidget {
  const _MilestoneEditorRow({
    required this.index,
    required this.milestone,
    required this.onEditTitle,
    required this.onPickDate,
    required this.onPickWeekdays,
    required this.onDelete,
  });

  final int index;
  final _MilestoneDraft milestone;
  final VoidCallback onEditTitle;
  final VoidCallback onPickDate;
  final VoidCallback onPickWeekdays;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: milestone.repeatsDaily || milestone.repeatWeekdays.isNotEmpty
            ? AppColors.sage.withValues(alpha: .1)
            : Colors.white.withValues(alpha: .46),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .64)),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.line_horizontal_3,
            size: 16,
            color: AppColors.muted,
          ),
          const SizedBox(width: 9),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .7),
              border: Border.all(color: AppColors.sage.withValues(alpha: .38)),
            ),
            child: Text('$index', style: AppText.bodyStrong),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onEditTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    milestone.title.text.trim().isEmpty
                        ? 'Task name'
                        : milestone.title.text,
                    style: AppText.bodyStrong.copyWith(
                      color: milestone.title.text.trim().isEmpty
                          ? AppColors.muted
                          : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(milestone.scheduleLabel, style: AppText.caption),
                ],
              ),
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            onPressed: onPickWeekdays,
            child: Icon(
              milestone.repeatsDaily
                  ? CupertinoIcons.repeat_1
                  : milestone.repeatWeekdays.isNotEmpty
                  ? CupertinoIcons.calendar_badge_plus
                  : CupertinoIcons.repeat,
              size: 20,
              color: AppColors.sage,
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            onPressed: onPickDate,
            child: const Icon(
              CupertinoIcons.calendar,
              size: 20,
              color: AppColors.sage,
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            onPressed: onDelete,
            child: Icon(
              CupertinoIcons.trash,
              size: 19,
              color: onDelete == null ? AppColors.muted : AppColors.clay,
            ),
          ),
        ],
      ),
    );
  }
}

class GoalFormField extends StatelessWidget {
  const GoalFormField({
    super.key,
    required this.label,
    required this.controller,
    this.onFocus,
    this.minLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback? onFocus;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.eyebrow),
        const SizedBox(height: 8),
        CupertinoTextField(
          controller: controller,
          onTap: onFocus,
          minLines: minLines,
          maxLines: minLines > 1 ? minLines + 2 : 1,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: appTextInputFormatters,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          style: AppText.bodyStrong,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .52),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: .72)),
          ),
        ),
      ],
    );
  }
}

const appTextInputFormatters = <TextInputFormatter>[
  CapitalizeFirstLetterFormatter(),
];

class CapitalizeFirstLetterFormatter extends TextInputFormatter {
  const CapitalizeFirstLetterFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final firstLetterIndex = text.indexOf(RegExp(r'[A-Za-zÀ-ž]'));
    if (firstLetterIndex < 0) return newValue;

    final first = text[firstLetterIndex];
    final upper = first.toUpperCase();
    if (first == upper) return newValue;

    return newValue.copyWith(
      text:
          text.substring(0, firstLetterIndex) +
          upper +
          text.substring(firstLetterIndex + 1),
    );
  }
}

class ChoiceWrap extends StatelessWidget {
  const ChoiceWrap({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
    this.labelFor,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;
  final String Function(String value)? labelFor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          GestureDetector(
            onTap: () => onSelected(value),
            child: CategoryPill(
              label: labelFor?.call(value) ?? value,
              active: value == selected,
            ),
          ),
      ],
    );
  }
}

class GoalDetailScreen extends StatelessWidget {
  const GoalDetailScreen({
    super.key,
    required this.goalId,
    required this.onBack,
    required this.onGoalCompleted,
  });

  final String? goalId;
  final VoidCallback onBack;
  final ValueChanged<String> onGoalCompleted;

  @override
  Widget build(BuildContext context) {
    final appState = LevelUpScope.of(context);
    final goal = _findGoal(appState);

    if (goal == null) {
      return AppScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BackButton(onBack: onBack),
            const SizedBox(height: 24),
            const EmptyGlassState(
              icon: CupertinoIcons.flag,
              title: 'Goal not found',
              subtitle: 'Go back to Goals and choose another goal.',
            ),
          ],
        ),
      );
    }

    final linkedTasks = appState.tasks
        .where((task) => task.goalId == goal.id)
        .toList(growable: false);
    final completedLinkedTasks = linkedTasks
        .where((task) => task.completed)
        .length;
    final nextTask = linkedTasks.cast<DailyTask?>().firstWhere(
      (task) => task != null && !task.completed,
      orElse: () => null,
    );

    return AppScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackButton(onBack: onBack),
          const SizedBox(height: 18),
          CategoryPill(label: goal.category),
          const SizedBox(height: 16),
          Text(goal.title, style: AppText.title),
          const SizedBox(height: 8),
          Text(goal.detail, style: AppText.body),
          const SizedBox(height: 28),
          GlassCard(
            child: Row(
              children: [
                RingProgress(
                  progress: goal.progress,
                  label: '${(goal.progress * 100).round()}%',
                  size: 88,
                  color: goal.completed ? AppColors.sage : AppColors.clay,
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.completed ? 'Goal completed' : 'Overall progress',
                        style: AppText.cardTitle,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        linkedTasks.isEmpty
                            ? 'No linked tasks yet'
                            : '$completedLinkedTasks/${linkedTasks.length} tasks complete',
                        style: AppText.body,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        nextTask?.title ?? 'Every linked task is complete',
                        style: AppText.bodyStrong,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Connected Daily Tasks', style: AppText.section),
          const SizedBox(height: 12),
          if (linkedTasks.isEmpty)
            const EmptyGlassState(
              icon: CupertinoIcons.checkmark_alt_circle,
              title: 'No tasks linked yet',
              subtitle: 'Daily tasks connected to this goal will appear here.',
            )
          else
            for (final task in linkedTasks) ...[
              TaskCard(
                icon: _taskIcon(task.category),
                tag: task.completed ? 'DONE' : task.category,
                title: task.title,
                subtitle: task.subtitle,
                done: task.completed,
                onTap: () => LevelUpScope.read(context).toggleTask(task.id),
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 24),
          GlassActionButton(
            icon: goal.completed
                ? CupertinoIcons.arrow_counterclockwise
                : CupertinoIcons.check_mark_circled,
            label: goal.completed ? 'Restore to active' : 'Mark goal complete',
            strong: true,
            onTap: () async {
              final state = LevelUpScope.read(context);
              if (goal.completed) {
                await state.restoreGoal(goal.id);
              } else {
                await state.completeGoal(goal.id);
                onGoalCompleted(goal.id);
              }
            },
          ),
          const SizedBox(height: 12),
          GlassActionButton(
            icon: CupertinoIcons.trash,
            label: 'Delete goal',
            strong: false,
            onTap: () => _confirmDelete(context, goal),
          ),
        ],
      ),
    );
  }

  Goal? _findGoal(LevelUpAppState appState) {
    if (goalId != null) {
      for (final goal in appState.goals) {
        if (goal.id == goalId) return goal;
      }
    }
    if (appState.activeGoals.isNotEmpty) return appState.activeGoals.first;
    if (appState.completedGoals.isNotEmpty) {
      return appState.completedGoals.first;
    }
    return null;
  }

  IconData _taskIcon(String category) {
    switch (category.toUpperCase()) {
      case 'HEALTH':
        return Icons.fitness_center;
      case 'CAREER':
        return CupertinoIcons.book;
      case 'FINANCE':
        return CupertinoIcons.money_pound_circle;
      case 'PERSONAL':
      case 'RELATIONSHIPS':
      case 'FAMILY':
        return CupertinoIcons.heart;
      default:
        return CupertinoIcons.sparkles;
    }
  }

  void _confirmDelete(BuildContext context, Goal goal) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Delete goal?'),
        content: Text('This will remove "${goal.title}" and its linked tasks.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await LevelUpScope.read(context).deleteGoal(goal.id);
              onBack();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 28),
      onPressed: onBack,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.chevron_left, size: 18),
          SizedBox(width: 4),
          Text('Your Goals'),
        ],
      ),
    );
  }
}

class GoalMilestonesCard extends StatelessWidget {
  const GoalMilestonesCard({
    super.key,
    required this.goal,
    required this.onToggle,
  });

  final Goal goal;
  final ValueChanged<Milestone> onToggle;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      borderRadius: 26,
      opacity: .50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Milestone Journey', style: AppText.section),
              ),
              Text(
                '${(goal.progress * 100).round()}%',
                style: AppText.bodyStrong.copyWith(color: AppColors.sage),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (goal.milestones.isEmpty)
            const Text('No milestones yet.', style: AppText.caption)
          else
            for (var i = 0; i < goal.milestones.length; i++) ...[
              MilestoneRow(
                index: i + 1,
                milestone: goal.milestones[i],
                isLast: i == goal.milestones.length - 1,
                onTap: () => onToggle(goal.milestones[i]),
              ),
            ],
        ],
      ),
    );
  }
}

class MilestoneRow extends StatelessWidget {
  const MilestoneRow({
    super.key,
    required this.index,
    required this.milestone,
    required this.isLast,
    required this.onTap,
  });

  final int index;
  final Milestone milestone;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = milestone.completed;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? AppColors.sage
                      : Colors.white.withValues(alpha: .58),
                  border: Border.all(
                    color: done
                        ? AppColors.sage
                        : AppColors.taupe.withValues(alpha: .5),
                    width: 1.4,
                  ),
                ),
                child: done
                    ? const Icon(
                        CupertinoIcons.check_mark,
                        color: Colors.white,
                        size: 18,
                      )
                    : Center(
                        child: Text(
                          '$index',
                          style: AppText.tiny.copyWith(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 34,
                  color: done
                      ? AppColors.sage.withValues(alpha: .45)
                      : AppColors.taupe.withValues(alpha: .25),
                ),
            ],
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    milestone.title,
                    style: AppText.bodyStrong.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? AppColors.muted : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (milestone.scheduleLabel.trim().isNotEmpty)
                        milestone.scheduleLabel,
                      done ? 'Completed' : 'Tap to mark complete',
                    ].join(' · '),
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GoalCompletionScreen extends StatelessWidget {
  const GoalCompletionScreen({
    super.key,
    required this.goalId,
    required this.backLabel,
    required this.onDone,
    required this.onClose,
    required this.onAddNew,
  });

  final String? goalId;
  final String backLabel;
  final VoidCallback onDone;
  final VoidCallback onClose;
  final VoidCallback onAddNew;

  @override
  Widget build(BuildContext context) {
    final appState = LevelUpScope.of(context);
    final goal = appState.goals.cast<Goal?>().firstWhere(
      (item) => item != null && item.id == goalId,
      orElse: () => null,
    );

    return AppScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            borderRadius: 30,
            opacity: .58,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    GlassIconButton(icon: CupertinoIcons.xmark, onTap: onClose),
                  ],
                ),
                const SizedBox(height: 4),
                Center(
                  child: Image.asset(
                    'assets/images/goal_completed.png',
                    width: 220,
                    height: 150,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Goal Completed',
                  style: AppText.eyebrow.copyWith(color: AppColors.sage),
                ),
                const SizedBox(height: 10),
                Text(goal?.title ?? 'Your goal', style: AppText.title),
                const SizedBox(height: 10),
                const Text(
                  'You climbed every step. This is proof that daily action becomes identity.',
                  style: AppText.body,
                ),
                const SizedBox(height: 20),
                if (goal != null)
                  for (final milestone in goal.milestones) ...[
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.check_mark_circled_solid,
                          color: AppColors.sage,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(milestone.title, style: AppText.caption),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          GlassActionButton(
            icon: CupertinoIcons.check_mark_circled,
            label: backLabel,
            strong: true,
            onTap: onDone,
          ),
          const SizedBox(height: 12),
          GlassActionButton(
            icon: CupertinoIcons.plus_circle,
            label: 'Add another goal',
            strong: false,
            onTap: onAddNew,
          ),
        ],
      ),
    );
  }
}

class DayCompleteOverlay extends StatelessWidget {
  const DayCompleteOverlay({
    super.key,
    required this.onClose,
    required this.onSeeGoals,
  });

  final VoidCallback onClose;
  final VoidCallback onSeeGoals;

  @override
  Widget build(BuildContext context) {
    final appState = LevelUpScope.of(context);
    final total = appState.todayTasks.length;
    final streak = appState.user.streakDays;

    return Positioned.fill(
      child: Container(
        color: AppColors.ink.withValues(alpha: .18),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              borderRadius: 34,
              opacity: .94,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.sage.withValues(alpha: .28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .8),
                      ),
                    ),
                    child: const Icon(
                      CupertinoIcons.flame_fill,
                      size: 34,
                      color: AppColors.clay,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Day Completed',
                    style: AppText.title,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$total/$total tasks done',
                    style: AppText.bodyStrong,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    streak > 0
                        ? 'Streak: $streak days'
                        : 'Your streak starts today',
                    style: AppText.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'You just gave your future self proof that you keep promises.',
                    style: AppText.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  GlassActionButton(
                    icon: CupertinoIcons.scope,
                    label: 'See Goal Progress',
                    strong: true,
                    onTap: onSeeGoals,
                  ),
                  const SizedBox(height: 10),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onClose,
                    child: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FutureMeScreen extends StatefulWidget {
  const FutureMeScreen({super.key, required this.onOpenGoal});

  final ValueChanged<String> onOpenGoal;

  @override
  State<FutureMeScreen> createState() => _FutureMeScreenState();
}

class _FutureMeScreenState extends State<FutureMeScreen> {
  final Set<String> _selectedAreas = {'All'};
  bool _aiImageGenerating = false;
  static const double _futureMeContentOverlap = -42;

  void _toggleArea(String area) {
    setState(() {
      if (area == 'All') {
        _selectedAreas
          ..clear()
          ..add('All');
        return;
      }

      _selectedAreas.remove('All');
      if (_selectedAreas.contains(area)) {
        _selectedAreas.remove(area);
      } else {
        _selectedAreas.add(area);
      }
      if (_selectedAreas.isEmpty) _selectedAreas.add('All');
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = LevelUpScope.of(context);
    final user = appState.user;
    final name = user.firstName.isEmpty ? 'there' : user.firstName;
    final vision = user.vision.trim().isEmpty
        ? 'I am healthy, confident and becoming the person I want to be.'
        : user.vision.trim();
    final goals = appState.activeGoals;
    final profilePhotoUrl = appState.authSession.photoUrl.trim();

    return AppScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppHeader(),
          const SizedBox(height: 30),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Future Me', style: AppText.title),
                    const SizedBox(height: 6),
                    Text(
                      'Design the life you want.',
                      style: AppText.body.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(-10, -25), // x, y
                child: const FutureVisionHeaderImage(),
              ),
            ],
          ),
          Transform.translate(
            offset: const Offset(0, _futureMeContentOverlap),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              borderRadius: 28,
              opacity: .42,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      FutureMeProfileAvatar(photoUrl: profilePhotoUrl),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: AppText.section.copyWith(fontSize: 24),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Future identity snapshot',
                              style: AppText.caption,
                            ),
                          ],
                        ),
                      ),
                      GlassIconButton(
                        icon: CupertinoIcons.pencil,
                        onTap: () => _showEditVision(context, vision),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FutureMeImagePicker(
                    imagePath: user.futureImagePath,
                    onTap: () => _showFutureImageDialog(context),
                    onRemove: user.futureImagePath.trim().isEmpty
                        ? null
                        : () => _removeFutureImage(context),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: SizedBox(
                      width: 210,
                      child: GlassActionButton(
                        icon: CupertinoIcons.sparkles,
                        label: _aiImageGenerating
                            ? 'Generating'
                            : 'Generate with AI',
                        strong: false,
                        onTap: _aiImageGenerating
                            ? null
                            : () => _generateFutureMeImage(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('MY VISION', style: AppText.eyebrow),
                  const SizedBox(height: 10),
                  Text(
                    vision,
                    style: AppText.section.copyWith(
                      fontSize: 18,
                      height: 1.4,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 0),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            borderRadius: 28,
            opacity: .54,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('LIFE AREAS', style: AppText.eyebrow),
                    const SizedBox(width: 8),
                    const Icon(
                      CupertinoIcons.info_circle,
                      size: 16,
                      color: AppColors.muted,
                    ),
                    const Spacer(),
                    Text(
                      'Tap an area to explore goals',
                      style: AppText.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                LifeAreaLabelFilters(
                  selectedAreas: _selectedAreas,
                  onAreaTap: _toggleArea,
                ),
                /*
                Previous radar version kept for possible future reuse:
                LifeAreasRadar(
                  selectedAreas: _selectedAreas,
                  onAreaTap: _toggleArea,
                ),
                */
                const SizedBox(height: 14),
                LifeAreaGoalList(
                  goals: goals,
                  selectedAreas: _selectedAreas,
                  areaVisions: user.areaVisions,
                  onOpenGoal: (goal) => _openLifeAreaGoal(context, goal),
                ),
                const SizedBox(height: 14),
                VerticalFutureTimelineCard(
                  selectedAreas: _selectedAreas,
                  goals: appState.goals,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditVision(BuildContext context, String currentVision) {
    final user = LevelUpScope.read(context).user;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => FutureVisionEditSheet(
        currentVision: currentVision,
        currentIdentities: user.identities,
        currentAreaVisions: user.areaVisions,
      ),
    );
  }

  Future<void> _showFutureImageDialog(BuildContext context) async {
    final appState = LevelUpScope.read(context);
    final pickedPath = await FutureImagePickerBridge.pickImage();
    if (pickedPath == null || pickedPath.trim().isEmpty) return;
    await appState.updateUser(futureImagePath: pickedPath.trim());
  }

  Future<void> _generateFutureMeImage(BuildContext context) async {
    final appState = LevelUpScope.read(context);
    final sourcePath = appState.user.futureImagePath.trim();
    if (sourcePath.isEmpty || sourcePath.startsWith('http')) {
      await _showFutureImageMessage(
        'Add your photo first',
        'Upload a current photo first, then Lucy can generate your Future Me image from your vision.',
      );
      return;
    }

    setState(() => _aiImageGenerating = true);
    final result = await AiService.instance.generateFutureImage(
      AiFutureImageRequest(
        sourceImagePath: sourcePath,
        vision: appState.user.vision,
        areaVisions: appState.user.areaVisions,
      ),
    );
    if (!mounted) return;
    setState(() => _aiImageGenerating = false);

    if (result == null) {
      await _showFutureImageMessage(
        'AI image is not connected yet',
        'The app is ready for a secure backend endpoint. Add LEVELUP_AI_BASE_URL when the image generation backend is deployed.',
      );
      return;
    }
    await appState.updateUser(futureImagePath: result.imageUrl);
  }

  Future<void> _showFutureImageMessage(String title, String message) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeFutureImage(BuildContext context) async {
    await LevelUpScope.read(context).updateUser(futureImagePath: '');
  }

  Future<void> _openLifeAreaGoal(BuildContext context, Goal goal) async {
    final appState = LevelUpScope.read(context);
    final existing = appState.goals.any((item) => item.id == goal.id);
    if (!existing) {
      await appState.addGoal(goal);
    }
    widget.onOpenGoal(goal.id);
  }
}

class FutureMeProfileAvatar extends StatelessWidget {
  const FutureMeProfileAvatar({super.key, required this.photoUrl});

  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl.isNotEmpty;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: .42),
        border: Border.all(color: Colors.white.withValues(alpha: .70)),
        boxShadow: [
          BoxShadow(
            color: AppColors.sage.withValues(alpha: .12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? SizedBox.expand(
              child: Image.network(
                photoUrl,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, _, _) => const Icon(
                  CupertinoIcons.person,
                  color: AppColors.ink,
                  size: 28,
                ),
              ),
            )
          : const Icon(CupertinoIcons.person, color: AppColors.ink, size: 28),
    );
  }
}

class FutureMeImagePicker extends StatelessWidget {
  const FutureMeImagePicker({
    super.key,
    required this.imagePath,
    required this.onTap,
    this.onRemove,
  });

  final String imagePath;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final trimmedPath = imagePath.trim();
    final isRemoteImage = trimmedPath.startsWith('http');
    final file = trimmedPath.isEmpty || isRemoteImage
        ? null
        : File(trimmedPath);
    final hasImage = isRemoteImage || (file != null && file.existsSync());
    return Center(
      child: SizedBox(
        width: 156,
        height: 156,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .44),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .70),
                      ),
                    ),
                    child: hasImage
                        ? isRemoteImage
                              ? Image.network(trimmedPath, fit: BoxFit.cover)
                              : Image.file(file!, fit: BoxFit.cover)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SoftIconBubble(
                                icon: CupertinoIcons.photo,
                                color: AppColors.sage,
                                size: 46,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Add image',
                                style: AppText.bodyStrong.copyWith(
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tap to choose',
                                style: AppText.caption,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            if (hasImage && onRemove != null)
              Positioned(
                top: -10,
                right: -10,
                child: GlassIconButton(
                  icon: CupertinoIcons.trash,
                  onTap: onRemove,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LifeAreaLabelFilters extends StatelessWidget {
  const LifeAreaLabelFilters({
    super.key,
    required this.selectedAreas,
    required this.onAreaTap,
  });

  static const areas = ['All', 'Health', 'Finance', 'Personal', 'Career'];

  final Set<String> selectedAreas;
  final ValueChanged<String> onAreaTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final area in areas)
          GestureDetector(
            onTap: () => onAreaTap(area),
            child: _CompletedFilterPill(
              label: area,
              active: selectedAreas.contains(area),
            ),
          ),
      ],
    );
  }
}

class LifeAreasRadar extends StatelessWidget {
  const LifeAreasRadar({
    super.key,
    required this.selectedAreas,
    required this.onAreaTap,
  });

  final Set<String> selectedAreas;
  final ValueChanged<String> onAreaTap;

  static const _areas = [
    'Health',
    'Finance',
    'Career',
    'Personal',
    'Relationships',
  ];
  static const _icons = [
    CupertinoIcons.heart,
    CupertinoIcons.money_dollar,
    CupertinoIcons.briefcase,
    CupertinoIcons.person,
    CupertinoIcons.person_2,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final positions = <Offset>[
            Offset(w * .50, 8),
            Offset(w * .84, 94),
            Offset(w * .72, 190),
            Offset(w * .28, 190),
            Offset(w * .16, 94),
          ];
          return Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: LifeRadarPainter())),
              for (var i = 0; i < _areas.length; i++)
                Positioned(
                  left: positions[i].dx - 46,
                  top: positions[i].dy,
                  width: 92,
                  child: GestureDetector(
                    onTap: () => onAreaTap(_areas[i]),
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            SoftIconBubble(
                              icon: _icons[i],
                              color: selectedAreas.contains(_areas[i])
                                  ? AppColors.sage
                                  : AppColors.muted,
                              size: 38,
                            ),
                            if (selectedAreas.contains(_areas[i]))
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF46782E),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.check_mark,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _areas[i],
                          textAlign: TextAlign.center,
                          style: AppText.caption.copyWith(
                            color: selectedAreas.contains(_areas[i])
                                ? AppColors.ink
                                : AppColors.muted,
                            fontWeight: selectedAreas.contains(_areas[i])
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class LifeRadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 8);
    final r = math.min(size.width, size.height) * .32;
    final grid = Paint()
      ..color = AppColors.hairline
      ..style = PaintingStyle.stroke;
    for (final k in [.35, .65, 1.0]) {
      final path = Path();
      for (var i = 0; i < 5; i++) {
        final a = -math.pi / 2 + i * math.pi * 2 / 5;
        final pt = center + Offset(math.cos(a), math.sin(a)) * r * k;
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      path.close();
      canvas.drawPath(path, grid);
    }
    final fill = Paint()
      ..color = AppColors.sage.withValues(alpha: .16)
      ..style = PaintingStyle.fill;
    final line = Paint()
      ..color = const Color(0xFF46782E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    const vals = [.92, .82, .86, .68, .76];
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * math.pi * 2 / 5;
      final pt = center + Offset(math.cos(a), math.sin(a)) * r * vals[i];
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LifeAreaGoalList extends StatelessWidget {
  const LifeAreaGoalList({
    super.key,
    required this.goals,
    required this.selectedAreas,
    required this.areaVisions,
    required this.onOpenGoal,
  });
  final List<Goal> goals;
  final Set<String> selectedAreas;
  final Map<String, String> areaVisions;
  final ValueChanged<Goal> onOpenGoal;

  static final _samplePlans = <String, _LifeAreaPlan>{
    'Health': _LifeAreaPlan(
      vision: 'Run a half marathon feeling strong and consistent.',
      taskRule: 'Run every Monday, Wednesday and Friday.',
      goals: [
        _SampleGoal('Run 5 km without stopping', DateTime(2026, 7, 31)),
        _SampleGoal('Run 10 km comfortably', DateTime(2026, 9, 30)),
        _SampleGoal('Run 15 km long run', DateTime(2026, 11, 30)),
        _SampleGoal('Complete a half marathon', DateTime(2027, 3, 28)),
      ],
    ),
    'Career': _LifeAreaPlan(
      vision: 'Create my own mobile app and bring it to real users.',
      taskRule: 'Work on the app for 30 minutes every day.',
      goals: [
        _SampleGoal('Create the MVP', DateTime(2026, 8, 31)),
        _SampleGoal('Test the POC with users', DateTime(2026, 10, 15)),
        _SampleGoal('Find the first investor', DateTime(2027, 1, 31)),
        _SampleGoal('Launch the app publicly', DateTime(2027, 4, 30)),
      ],
    ),
    'Finance': _LifeAreaPlan(
      vision: 'Build calm financial security and more freedom.',
      taskRule: 'Review spending every Friday and save every payday.',
      goals: [
        _SampleGoal('Save first \$1,000 buffer', DateTime(2026, 7, 15)),
        _SampleGoal(
          'Build a three month emergency fund',
          DateTime(2026, 12, 31),
        ),
        _SampleGoal('Automate monthly investing', DateTime(2027, 2, 28)),
        _SampleGoal('Pay down high interest debt', DateTime(2027, 6, 30)),
      ],
    ),
    'Personal': _LifeAreaPlan(
      vision: 'Become disciplined, grounded and proud of my daily choices.',
      taskRule: 'Read and journal for 20 minutes every evening.',
      goals: [
        _SampleGoal('Read 12 books', DateTime(2026, 12, 31)),
        _SampleGoal('Build a calm morning routine', DateTime(2026, 8, 31)),
        _SampleGoal(
          'Complete a 30 day confidence challenge',
          DateTime(2026, 9, 30),
        ),
        _SampleGoal(
          'Take one offline weekend each month',
          DateTime(2027, 1, 31),
        ),
      ],
    ),
    'Relationships': _LifeAreaPlan(
      vision: 'Build warm, present and reliable relationships.',
      taskRule: 'Reach out every Tuesday and plan quality time weekly.',
      goals: [
        _SampleGoal('Schedule weekly family calls', DateTime(2026, 7, 31)),
        _SampleGoal(
          'Plan two meaningful friend meetups',
          DateTime(2026, 9, 15),
        ),
        _SampleGoal('Create a monthly date ritual', DateTime(2026, 10, 31)),
        _SampleGoal('Practice active listening daily', DateTime(2026, 12, 31)),
      ],
    ),
  };

  IconData _iconFor(String area) {
    return area == 'Finance'
        ? CupertinoIcons.money_dollar
        : area == 'Career'
        ? CupertinoIcons.briefcase
        : area == 'Personal'
        ? CupertinoIcons.heart
        : Icons.fitness_center;
  }

  @override
  Widget build(BuildContext context) {
    final areas = selectedAreas.contains('All') || selectedAreas.isEmpty
        ? const ['Health', 'Finance', 'Personal', 'Career']
        : selectedAreas.toList();
    return Column(
      children: [
        for (final area in areas) ...[
          GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            borderRadius: 20,
            opacity: .58,
            child: Builder(
              builder: (context) {
                final areaGoals = goals
                    .where(
                      (g) => g.category.toLowerCase() == area.toLowerCase(),
                    )
                    .toList();
                final plan = _samplePlans[area] ?? _samplePlans['Health']!;
                final areaVision = areaVisions[area]?.trim().isNotEmpty == true
                    ? areaVisions[area]!.trim()
                    : plan.vision;
                final visibleGoals = areaGoals.take(2).toList();
                final sampleGoals = plan.goals
                    .take(2)
                    .map((sample) => sample.toGoal(area, plan))
                    .toList();
                final displayedGoals = visibleGoals.isEmpty
                    ? sampleGoals
                    : visibleGoals;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SoftIconBubble(
                          icon: _iconFor(area),
                          color: AppColors.sage,
                          size: 36,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(area, style: AppText.section)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Vision',
                      style: AppText.eyebrow.copyWith(fontSize: 10),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      areaVision,
                      style: AppText.caption.copyWith(
                        color: AppColors.ink,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${displayedGoals.length} goals',
                      style: AppText.bodyStrong.copyWith(
                        color: const Color(0xFF46782E),
                      ),
                    ),
                    const Divider(color: AppColors.hairline),
                    for (final goal in displayedGoals)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onOpenGoal(goal),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  goal.title,
                                  style: AppText.caption.copyWith(
                                    color: AppColors.ink,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(
                                CupertinoIcons.chevron_right,
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (area != areas.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _LifeAreaPlan {
  const _LifeAreaPlan({
    required this.vision,
    required this.taskRule,
    required this.goals,
  });

  final String vision;
  final String taskRule;
  final List<_SampleGoal> goals;

  static String defaultVisionFor(String area) {
    return switch (area) {
      'Finance' => 'Build calm financial security and more freedom.',
      'Personal' =>
        'Become disciplined, grounded and proud of my daily choices.',
      'Career' => 'Create my own mobile app and bring it to real users.',
      _ => 'Run a half marathon feeling strong and consistent.',
    };
  }
}

class _SampleGoal {
  const _SampleGoal(this.title, this.deadline);

  final String title;
  final DateTime deadline;

  Goal toGoal(String area, _LifeAreaPlan plan) {
    final normalizedArea = area.toUpperCase();
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return Goal(
      id: 'sample_${normalizedArea.toLowerCase()}_$slug',
      category: normalizedArea,
      title: title,
      detail: _formatDeadline(deadline),
      progress: 0,
      vision: plan.vision,
      timeline: plan.goals.map((goal) => goal.title).join(' → '),
      completed: false,
      milestones: [
        Milestone(
          id: 'sample_${normalizedArea.toLowerCase()}_${slug}_milestone_0',
          title: title,
          subtitle: plan.taskRule,
          dueDate: deadline,
          repeatWeekdays: _weekdaysFor(area),
        ),
      ],
    );
  }

  static List<int> _weekdaysFor(String area) {
    return switch (area) {
      'Career' => const [1, 2, 3, 4, 5, 6, 7],
      'Finance' => const [5],
      'Relationships' => const [2, 6],
      'Personal' => const [1, 2, 3, 4, 5, 6, 7],
      _ => const [1, 3, 5],
    };
  }

  static String _formatDeadline(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class VerticalFutureTimelineCard extends StatelessWidget {
  const VerticalFutureTimelineCard({
    super.key,
    required this.selectedAreas,
    required this.goals,
  });

  final Set<String> selectedAreas;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final areas = selectedAreas.contains('All') || selectedAreas.isEmpty
        ? const ['Health', 'Finance', 'Personal', 'Career']
        : selectedAreas.toList();
    final items = [
      for (final goal in goals)
        if (areas.any(
          (area) => goal.category.toLowerCase() == area.toLowerCase(),
        ))
          (
            _timelineDate(goal),
            goal.title,
            _displayArea(goal.category),
            goal.completed,
          ),
      ('2028+', 'Best Version of Me', 'Life', false),
    ];

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      borderRadius: 22,
      opacity: .54,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('TIMELINE', style: AppText.eyebrow),
              const SizedBox(width: 8),
              const Icon(
                CupertinoIcons.info_circle,
                size: 16,
                color: AppColors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  areas.join(' · '),
                  style: AppText.caption.copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < items.length; i++)
            _VerticalTimelineItem(
              date: items[i].$1,
              title: items[i].$2,
              area: items[i].$3,
              done: items[i].$4,
              last: i == items.length - 1,
            ),
        ],
      ),
    );
  }

  String _timelineDate(Goal goal) {
    if (goal.completedAt != null) return '${goal.completedAt!.year}';
    final detail = goal.detail.trim();
    if (detail.isEmpty) return goal.startedAt == null ? 'Future' : 'Now';
    final first = detail.split('·').first.trim();
    return first.isEmpty ? 'Future' : first;
  }

  String _displayArea(String category) {
    final lower = category.toLowerCase();
    return lower.isEmpty
        ? 'Life'
        : '${lower[0].toUpperCase()}${lower.substring(1)}';
  }
}

class _VerticalTimelineItem extends StatelessWidget {
  const _VerticalTimelineItem({
    required this.date,
    required this.title,
    required this.area,
    required this.done,
    required this.last,
  });

  final String date;
  final String title;
  final String area;
  final bool done;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? const Color(0xFF46782E)
                    : Colors.white.withValues(alpha: .70),
                border: Border.all(color: const Color(0xFF46782E), width: 2),
              ),
              child: done
                  ? const Icon(
                      CupertinoIcons.check_mark,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
            if (!last)
              Container(
                width: 2,
                height: 42,
                color: const Color(0xFF46782E).withValues(alpha: .35),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: AppText.caption.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(title, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  area,
                  style: AppText.caption.copyWith(
                    color: const Color(0xFF46782E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class TimelinePainter extends CustomPainter {
  const TimelinePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * .46;
    final xs = [32.0, size.width * .36, size.width * .59, size.width * .82];
    final p = Paint()
      ..color = const Color(0xFF46782E)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, y + 18), Offset(size.width, y - 10), p);
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    final labels = [
      ('Oct 2025', 'Run a Half\nMarathon', 'Health'),
      ('2026', 'Medical School\nEntry', 'Career'),
      ('2027', 'Emergency Fund\nComplete', 'Finance'),
      ('2028+', 'Best Version\nof Me', 'Life'),
    ];
    for (var i = 0; i < xs.length; i++) {
      final x = xs[i];
      final yy = y + 18 - i * 9;
      canvas.drawCircle(
        Offset(x, yy),
        i < 2 ? 15 : 11,
        Paint()..color = i < 2 ? const Color(0xFF46782E) : Colors.white,
      );
      canvas.drawCircle(
        Offset(x, yy),
        i < 2 ? 15 : 11,
        Paint()
          ..color = const Color(0xFF46782E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      tp.text = TextSpan(
        text: labels[i].$1,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
      );
      tp.layout(maxWidth: 80);
      tp.paint(canvas, Offset(x - tp.width / 2, 0));
      tp.text = TextSpan(
        text: labels[i].$2,
        style: const TextStyle(fontSize: 12, color: AppColors.ink),
      );
      tp.layout(maxWidth: 95);
      tp.paint(canvas, Offset(x - tp.width / 2, yy + 24));
      tp.text = TextSpan(
        text: labels[i].$3,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF46782E),
          fontWeight: FontWeight.w700,
        ),
      );
      tp.layout(maxWidth: 80);
      tp.paint(canvas, Offset(x - tp.width / 2, yy + 62));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FutureMeStep extends StatelessWidget {
  const FutureMeStep({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (active ? AppColors.sage : AppColors.cream).withValues(
              alpha: .44,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .74)),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? AppColors.ink : AppColors.muted,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.cardTitle),
              const SizedBox(height: 4),
              Text(subtitle, style: AppText.caption),
            ],
          ),
        ),
      ],
    );
  }
}

class FutureMeConnector extends StatelessWidget {
  const FutureMeConnector({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 18, top: 8, bottom: 8),
      child: Container(
        width: 2,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          color: (active ? AppColors.sage : AppColors.cream).withValues(
            alpha: .62,
          ),
        ),
      ),
    );
  }
}

class FutureVisionEditSheet extends StatefulWidget {
  const FutureVisionEditSheet({
    super.key,
    required this.currentVision,
    required this.currentIdentities,
    required this.currentAreaVisions,
  });

  final String currentVision;
  final List<String> currentIdentities;
  final Map<String, String> currentAreaVisions;

  @override
  State<FutureVisionEditSheet> createState() => _FutureVisionEditSheetState();
}

class _FutureVisionEditSheetState extends State<FutureVisionEditSheet> {
  static const _areas = ['Health', 'Finance', 'Personal', 'Career'];

  late final Map<String, TextEditingController> _controllers = {
    for (final area in _areas)
      area: TextEditingController(
        text:
            widget.currentAreaVisions[area] ??
            _LifeAreaPlan.defaultVisionFor(area),
      ),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        28 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        borderRadius: 28,
        opacity: .92,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * .72,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Edit Vision', style: AppText.section),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 32),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('Vision for each life area', style: AppText.eyebrow),
                const SizedBox(height: 10),
                for (final area in _areas) ...[
                  Text(area, style: AppText.bodyStrong),
                  const SizedBox(height: 6),
                  CupertinoTextField(
                    controller: _controllers[area],
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: appTextInputFormatters,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 12,
                    ),
                    style: AppText.bodyStrong,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .52),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 6),
                GlassActionButton(
                  icon: CupertinoIcons.check_mark_circled,
                  label: 'Save visions',
                  strong: true,
                  onTap: () async {
                    final areaVisions = {
                      for (final area in _areas)
                        area: _controllers[area]!.text.trim(),
                    };
                    final mainVision = areaVisions.values
                        .where((value) => value.trim().isNotEmpty)
                        .join(' ');
                    await LevelUpScope.read(context).updateUser(
                      vision: mainVision.trim().isEmpty
                          ? widget.currentVision
                          : mainVision,
                      identities: widget.currentIdentities,
                      areaVisions: areaVisions,
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AddVisionSheet extends StatefulWidget {
  const AddVisionSheet({super.key, required this.onCreate});

  final ValueChanged<VisionData> onCreate;

  @override
  State<AddVisionSheet> createState() => _AddVisionSheetState();
}

class _AddVisionSheetState extends State<AddVisionSheet> {
  final _title = TextEditingController(text: 'Speak fluent Spanish');
  final _goal = TextEditingController(text: 'Complete B1 conversation plan');
  final _timeline = TextEditingController(
    text: 'Daily phrases → tutor calls → B1 trip',
  );
  String _area = 'PERSONAL';
  String _goalMode = 'Pair existing goal';

  @override
  void dispose() {
    _title.dispose();
    _goal.dispose();
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        borderRadius: 28,
        opacity: .9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Add New Vision', style: AppText.section),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(32, 32),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Icon(CupertinoIcons.xmark_circle_fill),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GoalFormField(label: 'Vision statement', controller: _title),
            const SizedBox(height: 14),
            const Text('Life Area', style: AppText.eyebrow),
            const SizedBox(height: 8),
            ChoiceWrap(
              values: const [
                'HEALTH',
                'CAREER',
                'FINANCE',
                'PERSONAL',
                'FAMILY',
              ],
              selected: _area,
              onSelected: (value) => setState(() => _area = value),
            ),
            const SizedBox(height: 14),
            const Text('Goal pairing', style: AppText.eyebrow),
            const SizedBox(height: 8),
            ChoiceWrap(
              values: const ['Pair existing goal', 'Create new goal'],
              selected: _goalMode,
              onSelected: (value) => setState(() => _goalMode = value),
            ),
            const SizedBox(height: 12),
            GoalFormField(
              label: _goalMode == 'Create new goal'
                  ? 'New goal attached to this vision'
                  : 'Existing goal to connect',
              controller: _goal,
            ),
            const SizedBox(height: 12),
            GoalFormField(label: 'Vision timeline', controller: _timeline),
            const SizedBox(height: 18),
            GlassActionButton(
              icon: CupertinoIcons.sparkles,
              label: 'Create vision',
              strong: true,
              onTap: () {
                final now = DateTime.now().millisecondsSinceEpoch;
                widget.onCreate(
                  VisionData(
                    id: 'vision_$now',
                    title: _title.text,
                    selected: true,
                    goals: [
                      VisionGoalData(_goal.text, 'Connected to $_area', .08),
                    ],
                    milestones: [
                      VisionMilestoneData(
                        202606,
                        'NOW',
                        _timeline.text.split('→').first.trim(),
                        VisionStage.now,
                      ),
                      VisionMilestoneData(
                        202612,
                        'DEC 2026',
                        _timeline.text.contains('→')
                            ? _timeline.text.split('→').last.trim()
                            : _title.text,
                        VisionStage.future,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class MotivateScreen extends StatefulWidget {
  const MotivateScreen({super.key});

  @override
  State<MotivateScreen> createState() => _MotivateScreenState();
}

class _MotivateScreenState extends State<MotivateScreen> {
  final Set<String> _played = {};

  static const _videos = [
    ('video_01', 'By Lucy', '0:00', 'assets/videos/video_01.mp4'),
    (
      'video_02',
      'What to do when\nmotivation disappears',
      '4:58',
      'assets/videos/video_02.mp4',
    ),
    ('video_03', 'Building\ndiscipline', '4:21', 'assets/videos/video_03.mp4'),
  ];

  Future<void> _openVideo(
    BuildContext context, {
    required String id,
    required String title,
    required String storagePath,
  }) async {
    if (storagePath.isEmpty) {
      setState(() => _played.add(id));
      return;
    }
    if (_isFlutterTest) {
      setState(() => _played.add(id));
      return;
    }

    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CupertinoAlertDialog(
        content: Padding(
          padding: EdgeInsets.only(top: 8),
          child: CupertinoActivityIndicator(),
        ),
      ),
    );

    try {
      final url = await FirebaseStorage.instance
          .ref(storagePath)
          .getDownloadURL();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => FirebaseLucyVideoPlayer(
            title: title.replaceAll('\n', ' '),
            videoUrl: url,
          ),
        ),
      );
      if (mounted) setState(() => _played.add(id));
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Video unavailable'),
          content: const Text(
            'Lucy video could not be loaded from Firebase Storage.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  bool get _isFlutterTest =>
      Platform.environment.containsKey('FLUTTER_TEST') ||
      Platform.environment.containsKey('DART_TEST') ||
      WidgetsBinding.instance.runtimeType.toString().contains(
        'TestWidgetsFlutterBinding',
      );

  @override
  Widget build(BuildContext context) {
    return AppScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppHeader(),
          const SizedBox(height: 30),
          const Text('Stay motivated', style: AppText.title),
          const SizedBox(height: 8),
          Text(
            'Your daily fuel.',
            style: AppText.body.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 6),
          const ScienceFuelSection(),
          const SizedBox(height: 26),
          const Text('BY LUCY', style: AppText.eyebrow),
          const SizedBox(height: 8),
          const Text(
            'Short lessons to keep you moving.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          for (final video in _videos)
            MotivationVideoRow(
              title: video.$2,
              duration: video.$3,
              played: _played.contains(video.$1),
              onPlay: () => _openVideo(
                context,
                id: video.$1,
                title: video.$2,
                storagePath: video.$4,
              ),
            ),
        ],
      ),
    );
  }
}

class FirebaseLucyVideoPlayer extends StatefulWidget {
  const FirebaseLucyVideoPlayer({
    super.key,
    required this.title,
    required this.videoUrl,
  });

  final String title;
  final String videoUrl;

  @override
  State<FirebaseLucyVideoPlayer> createState() =>
      _FirebaseLucyVideoPlayerState();
}

class _FirebaseLucyVideoPlayerState extends State<FirebaseLucyVideoPlayer> {
  late final VideoPlayerController _controller =
      VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.setLooping(false);
      await _controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Video could not be played.');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(
            child: _error != null
                ? Text(_error!, style: const TextStyle(color: Colors.white))
                : !_ready
                ? const CupertinoActivityIndicator(color: Colors.white)
                : AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_ready)
            Positioned(
              left: 24,
              right: 24,
              bottom: MediaQuery.of(context).padding.bottom + 28,
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: AppColors.sage,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ScienceFuelSection extends StatelessWidget {
  const ScienceFuelSection({super.key});

  static const _items = [
    ScienceFuelItem(
      title: 'Mindset',
      subtitle: 'Build mental strength',
      icon: CupertinoIcons.leaf_arrow_circlepath,
      body:
          'A useful mindset is not pretending everything is easy. It is treating ability as something you can train through feedback, effort and better strategies.',
      action:
          'Today: when a task feels hard, write one sentence: “This is training, not proof that I can’t do it.” Then do the smallest next rep.',
      source: 'Based on growth mindset and self-regulation research.',
    ),
    ScienceFuelItem(
      title: 'Discipline',
      subtitle: 'Master your habits',
      icon: Icons.fitness_center,
      body:
          'Discipline gets easier when the action is tied to a concrete cue. “If it is 9:00, then I open my task list” beats a vague intention.',
      action:
          'Today: choose one if-then plan for your most important task and attach it to a time, place or existing routine.',
      source: 'Based on implementation intention research.',
    ),
    ScienceFuelItem(
      title: 'Growth',
      subtitle: 'Become your best self',
      icon: CupertinoIcons.flag_fill,
      body:
          'Progress feels more motivating when goals support autonomy, competence and connection. A good goal should feel chosen, doable and meaningful.',
      action:
          'Today: edit one goal so it answers: why this matters, what the next step is, and when you will do it.',
      source: 'Based on self-determination theory.',
    ),
    ScienceFuelItem(
      title: 'Motivation',
      subtitle: 'Create momentum',
      icon: CupertinoIcons.flame_fill,
      body:
          'Motivation often follows action rather than arriving before it. Starting small lowers friction and gives the brain evidence that movement is possible.',
      action:
          'Today: choose a two-minute version of one task. Begin there, then decide whether to continue.',
      source: 'Based on behavioral activation and habit formation research.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in _items)
                  SizedBox(
                    width: tileWidth,
                    child: ScienceFuelTile(
                      item: item,
                      onTap: () => _showFuelDetail(context, item),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  static void _showFuelDetail(BuildContext context, ScienceFuelItem item) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
        child: GlassCard(
          borderRadius: 28,
          padding: const EdgeInsets.all(22),
          opacity: .94,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SoftIconBubble(icon: item.icon, color: AppColors.sage),
                  const SizedBox(width: 12),
                  Expanded(child: Text(item.title, style: AppText.section)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Icon(CupertinoIcons.xmark_circle_fill),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(item.body, style: AppText.body),
              const SizedBox(height: 14),
              Text(item.action, style: AppText.bodyStrong),
              const SizedBox(height: 12),
              Text(item.source, style: AppText.caption),
            ],
          ),
        ),
      ),
    );
  }
}

class ScienceFuelTile extends StatelessWidget {
  const ScienceFuelTile({super.key, required this.item, required this.onTap});

  final ScienceFuelItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 104,
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
          borderRadius: 16,
          opacity: .42,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SoftIconBubble(icon: item.icon, color: AppColors.sage, size: 32),
              const Spacer(),
              Text(item.title, style: AppText.bodyStrong, maxLines: 1),
              const SizedBox(height: 2),
              Text(item.subtitle, style: AppText.tiny, maxLines: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class ScienceFuelItem {
  const ScienceFuelItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.body,
    required this.action,
    required this.source,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String body;
  final String action;
  final String source;
}

class MotivationVideoRow extends StatelessWidget {
  const MotivationVideoRow({
    super.key,
    required this.title,
    required this.duration,
    required this.played,
    required this.onPlay,
  });
  final String title;
  final String duration;
  final bool played;
  final VoidCallback onPlay;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(8),
        borderRadius: 18,
        opacity: .50,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Image.asset(
                    'assets/images/lucy_portrait.png',
                    width: 150,
                    height: 90,
                    fit: BoxFit.cover,
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: onPlay,
                      child: Center(
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            color: Colors.black.withValues(alpha: .10),
                          ),
                          child: Icon(
                            played
                                ? CupertinoIcons.check_mark
                                : CupertinoIcons.play_fill,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      color: Colors.black.withValues(alpha: .55),
                      child: Text(
                        duration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: AppText.section)),
            if (played)
              const Icon(
                CupertinoIcons.check_mark_circled,
                color: AppColors.sage,
              ),
          ],
        ),
      ),
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({super.key, this.showAvatar = false, this.onAvatarTap});

  final bool showAvatar;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GlassIconButton(
          icon: CupertinoIcons.line_horizontal_3,
          onTap: () => _showMenuSheet(context),
        ),
        const SizedBox(width: 12),
        const Logo(),
        const Spacer(),
        if (showAvatar)
          GestureDetector(
            onTap: onAvatarTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/images/lucy_portrait.png',
                    width: 38,
                    height: 38,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7302A),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.background,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _showMenuSheet(BuildContext context) {
    final parentContext = context;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close menu',
      barrierColor: AppColors.ink.withValues(alpha: .18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 18),
        child: Align(
          alignment: Alignment.topLeft,
          child: LeftMenuPanel(rootContext: parentContext),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        );
      },
    );
  }
}

class LucyAvatarButton extends StatelessWidget {
  const LucyAvatarButton({
    super.key,
    required this.onTap,
    this.hasUnread = false,
  });

  final VoidCallback onTap;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: Image.asset(
              'assets/images/lucy_portrait.png',
              width: 50,
              height: 50,
              fit: BoxFit.cover,
            ),
          ),
          if (hasUnread)
            Positioned(
              top: -1,
              right: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7302A),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class LeftMenuPanel extends StatelessWidget {
  const LeftMenuPanel({super.key, required this.rootContext});

  final BuildContext rootContext;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 286,
      height:
          MediaQuery.of(context).size.height -
          MediaQuery.of(context).padding.top -
          18,
      child: GlassCard(
        borderRadius: 0,
        opacity: .84,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Logo(),
            const SizedBox(height: 22),
            MenuRow(
              icon: CupertinoIcons.person_crop_circle,
              label: 'User login',
              onTap: () => _open(
                context,
                const MenuDetailPage(type: MenuPageType.login),
              ),
            ),
            MenuRow(
              icon: CupertinoIcons.gear_alt,
              label: 'Settings',
              onTap: () => _open(
                context,
                const MenuDetailPage(type: MenuPageType.settings),
              ),
            ),
            MenuRow(
              icon: CupertinoIcons.info_circle,
              label: 'About Level Up',
              onTap: () => _open(
                context,
                const MenuDetailPage(type: MenuPageType.about),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext menuContext, Widget page) {
    Navigator.of(menuContext).pop();
    Navigator.of(rootContext).push(CupertinoPageRoute(builder: (_) => page));
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .48),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .7)),
            ),
            child: Icon(icon, size: 20, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}

class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.clay),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppText.bodyStrong)),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: AppColors.taupe,
            ),
          ],
        ),
      ),
    );
  }
}

class Logo extends StatelessWidget {
  const Logo({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 106,
      height: 31,
      child: Image.asset(
        'assets/images/levelup_logo.png',
        fit: BoxFit.fitWidth,
      ),
    );
  }
}

enum MenuPageType { login, settings, about }

class MenuDetailPage extends StatelessWidget {
  const MenuDetailPage({super.key, required this.type});

  final MenuPageType type;

  String get title => switch (type) {
    MenuPageType.login => 'User login',
    MenuPageType.settings => 'Settings',
    MenuPageType.about => 'About Level Up',
  };

  String get subtitle => switch (type) {
    MenuPageType.login => 'Keep your goals, visions, and progress synced.',
    MenuPageType.settings => 'Control coaching rhythm, privacy, and reminders.',
    MenuPageType.about =>
      'A future-self system for goals that become identity.',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const LiquidBackground(),
          AppScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.chevron_left, size: 18),
                      SizedBox(width: 4),
                      Text('Menu'),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Logo(),
                const SizedBox(height: 26),
                Text(title, style: AppText.title),
                const SizedBox(height: 8),
                Text(subtitle, style: AppText.body),
                const SizedBox(height: 24),
                ..._content(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    return switch (type) {
      MenuPageType.login => [
        AccountPreviewCard(
          session: LevelUpScope.of(context).authSession,
          user: LevelUpScope.of(context).user,
        ),
        const SizedBox(height: 14),
        MenuInfoCard(
          icon: CupertinoIcons.lock_shield,
          title: LevelUpScope.of(context).isSignedIn
              ? 'Signed in with Google'
              : 'Guest mode is active',
          body: LevelUpScope.of(context).isSignedIn
              ? 'Your LevelUp account is connected. You can continue using the app normally or sign out to return to guest mode.'
              : 'Guest mode keeps everything on this device. Sign in with Google when you want your LevelUp data ready for account sync.',
        ),
        if (!LevelUpScope.of(context).isSignedIn) ...[
          const SizedBox(height: 14),
          GlassActionButton(
            icon: CupertinoIcons.person_crop_circle_badge_checkmark,
            label: 'Continue with Google',
            strong: true,
            onTap: () => _showSignInDialog(
              context,
              LevelUpScope.read(context).signInWithGoogle,
            ),
          ),
          const SizedBox(height: 10),
          GlassActionButton(
            icon: CupertinoIcons.person,
            label: 'Continue as guest',
            onTap: () async {
              await LevelUpScope.read(context).continueAsGuest();
              if (context.mounted) {
                await _showGuestModeDialog(context);
              }
            },
          ),
        ],
        if (LevelUpScope.of(context).isSignedIn) ...[
          const SizedBox(height: 14),
          GlassActionButton(
            icon: CupertinoIcons.square_arrow_right,
            label: 'Sign out to guest mode',
            onTap: () => LevelUpScope.read(context).signOutToGuest(),
          ),
        ],
      ],
      MenuPageType.settings => [
        GlassActionButton(
          icon: CupertinoIcons.person_crop_circle,
          label: 'Edit name',
          onTap: () => _showEditNameDialog(context),
        ),
        const SizedBox(height: 12),
        SettingsToggleRow(
          title: 'Zprávy od Lucy',
          enabled: LevelUpScope.of(
            context,
          ).reminderSettings.lucyMessagesEnabled,
          onChanged: (enabled) {
            final appState = LevelUpScope.read(context);
            appState.updateReminderSettings(
              appState.reminderSettings.copyWith(lucyMessagesEnabled: enabled),
            );
          },
        ),
        SettingsToggleRow(
          title: 'Morning Lucy message',
          enabled: LevelUpScope.of(context).reminderSettings.morningEnabled,
          onChanged: (enabled) {
            final appState = LevelUpScope.read(context);
            appState.updateReminderSettings(
              appState.reminderSettings.copyWith(morningEnabled: enabled),
            );
          },
        ),
        SettingsToggleRow(
          title: 'Daily reflection reminder',
          enabled: LevelUpScope.of(context).reminderSettings.eveningEnabled,
          onChanged: (enabled) {
            final appState = LevelUpScope.read(context);
            appState.updateReminderSettings(
              appState.reminderSettings.copyWith(eveningEnabled: enabled),
            );
          },
        ),
      ],
      MenuPageType.about => const [
        MenuInfoCard(
          icon: CupertinoIcons.sparkles,
          title: 'Why Level Up exists',
          body:
              'Level Up connects today’s tasks to the person the user is becoming. The app is part tracker, part coach, part future-self journal.',
        ),
        SizedBox(height: 14),
        MenuInfoCard(
          icon: CupertinoIcons.scope,
          title: 'Core loop',
          body:
              'Choose visions, turn them into goals, complete daily tasks, and watch the timeline become proof.',
        ),
      ],
    };
  }

  Future<void> _showSignInDialog(
    BuildContext context,
    Future<String> Function() action,
  ) async {
    final message = await action();
    if (!context.mounted) return;

    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Account'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGuestModeDialog(BuildContext context) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Guest mode active'),
        content: const Text(
          'Your data stays saved locally on this device, which is ready for your testing flow.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditNameDialog(BuildContext context) async {
    final appState = LevelUpScope.read(context);
    final controller = TextEditingController(text: appState.user.name);

    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Edit name'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Your name',
            textCapitalization: TextCapitalization.words,
            inputFormatters: appTextInputFormatters,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await appState.updateUser(name: name);
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
  }
}

class AccountPreviewCard extends StatelessWidget {
  const AccountPreviewCard({
    super.key,
    required this.session,
    required this.user,
  });

  final AuthSession session;
  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final title = session.isSignedIn
        ? session.displayName.trim()
        : user.name.trim().isEmpty
        ? 'Guest'
        : user.name.trim();
    final subtitle = session.isSignedIn
        ? session.email.trim().isEmpty
              ? 'Signed in with ${session.provider.name}'
              : session.email.trim()
        : 'Guest mode · local data only';

    return GlassCard(
      child: Row(
        children: [
          ClipOval(
            child: session.photoUrl.trim().isNotEmpty
                ? Image.network(
                    session.photoUrl.trim(),
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Image.asset(
                      'assets/images/lucy_portrait.png',
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                  )
                : Image.asset(
                    'assets/images/lucy_portrait.png',
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardTitle),
                const SizedBox(height: 4),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MenuInfoCard extends StatelessWidget {
  const MenuInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.clay),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                const SizedBox(height: 5),
                Text(body, style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.title,
    required this.enabled,
    this.onChanged,
  });

  final String title;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(title, style: AppText.bodyStrong)),
            CupertinoSwitch(value: enabled, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class HomeWidgetPreviewSection extends StatelessWidget {
  const HomeWidgetPreviewSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = LevelUpScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Home screen widgets', style: AppText.cardTitle),
        const SizedBox(height: 10),
        QuoteHomeWidgetPreview(appState: appState),
        const SizedBox(height: 12),
        TasksHomeWidgetPreview(tasks: appState.todayTasks.take(3).toList()),
      ],
    );
  }
}

class QuoteHomeWidgetPreview extends StatelessWidget {
  const QuoteHomeWidgetPreview({super.key, required this.appState});

  final LevelUpAppState appState;

  @override
  Widget build(BuildContext context) {
    final quote = LucyMessageCatalog.quoteOfTheDay(DateTime.now());

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      borderRadius: 34,
      opacity: .36,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                CupertinoIcons.quote_bubble,
                size: 18,
                color: AppColors.clay,
              ),
              SizedBox(width: 8),
              Text('Daily quote widget', style: AppText.bodyStrong),
            ],
          ),
          const SizedBox(height: 10),
          Text(quote, style: AppText.identity),
          const SizedBox(height: 8),
          const Text('Rotates daily', style: AppText.caption),
        ],
      ),
    );
  }
}

class TasksHomeWidgetPreview extends StatelessWidget {
  const TasksHomeWidgetPreview({super.key, required this.tasks});

  final List<DailyTask> tasks;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      borderRadius: 24,
      opacity: .5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Today’s Tasks widget', style: AppText.bodyStrong),
          const SizedBox(height: 12),
          if (tasks.isEmpty)
            const Text('No tasks planned for today', style: AppText.caption)
          else
            for (final task in tasks) ...[
              WidgetTaskRow(label: task.title, done: task.completed),
              if (task != tasks.last) const SizedBox(height: 9),
            ],
        ],
      ),
    );
  }
}

class WidgetTaskRow extends StatelessWidget {
  const WidgetTaskRow({super.key, required this.label, this.done = false});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: done ? AppColors.sage : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: done ? AppColors.sage : AppColors.taupe,
              width: 1.6,
            ),
          ),
          child: done
              ? const Icon(
                  CupertinoIcons.check_mark,
                  size: 12,
                  color: Colors.white,
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: AppText.caption)),
      ],
    );
  }
}

class AppScrollView extends StatelessWidget {
  const AppScrollView({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 104),
        child: child,
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 22,
    this.opacity = .36,
  });

  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: .78),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .07),
                blurRadius: 30,
                spreadRadius: 0,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class TodayGlassCard extends StatelessWidget {
  const TodayGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 22,
  });

  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .36),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: .78),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .07),
                blurRadius: 30,
                spreadRadius: 0,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class LiquidBackground extends StatelessWidget {
  const LiquidBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.background),
      child: Stack(
        children: [
          Positioned(
            top: 120,
            right: -70,
            child: _Glow(color: Colors.black, size: 190, opacity: .12),
          ),
          Positioned(
            top: 420,
            left: -80,
            child: _Glow(color: Colors.black, size: 180, opacity: .08),
          ),
          Positioned(
            bottom: 160,
            right: -60,
            child: _Glow(color: Colors.white, size: 160, opacity: .08),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size, required this.opacity});

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: opacity),
          ),
        ),
      ),
    );
  }
}

class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const tabs = [
    (CupertinoIcons.house, 'Home'),
    (CupertinoIcons.scope, 'Goals'),
    (CupertinoIcons.sparkles, 'Future Me'),
    (CupertinoIcons.sun_max, 'Motivate'),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      borderRadius: 24,
      opacity: .68,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: currentIndex == i
                        ? Colors.white.withValues(alpha: .42)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i == 0)
                        HomeTabIcon(
                          color: currentIndex == i
                              ? AppColors.clay
                              : AppColors.taupe,
                        )
                      else
                        Icon(
                          tabs[i].$1,
                          size: 20,
                          color: currentIndex == i
                              ? AppColors.clay
                              : AppColors.muted,
                        ),
                      const SizedBox(height: 3),
                      Text(
                        tabs[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: currentIndex == i
                              ? AppColors.clay
                              : AppColors.taupe,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HomeTabIcon extends StatelessWidget {
  const HomeTabIcon({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 21,
      height: 21,
      child: CustomPaint(painter: HomeTabIconPainter(color)),
    );
  }
}

class HomeTabIconPainter extends CustomPainter {
  HomeTabIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * .18, h * .48)
      ..lineTo(w * .50, h * .18)
      ..lineTo(w * .82, h * .48)
      ..lineTo(w * .82, h * .86)
      ..lineTo(w * .18, h * .86)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant HomeTabIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class RingProgress extends StatelessWidget {
  const RingProgress({
    super.key,
    required this.progress,
    required this.label,
    required this.size,
    required this.color,
    this.labelStyle,
  });

  final double progress;
  final String label;
  final double size;
  final Color color;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: RingPainter(progress: progress, color: color),
        child: Center(child: Text(label, style: labelStyle ?? AppText.ring)),
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = AppColors.hairline;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(center, radius, bg);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 4,
        value: value,
        backgroundColor: AppColors.hairline,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

class StatPill extends StatelessWidget {
  const StatPill({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .48),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .72),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: .12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: AppText.statValue),
                Text(label, style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.selectedDate,
    required this.onOpenMonth,
    required this.onSelectDate,
  });

  final DateTime selectedDate;
  final VoidCallback onOpenMonth;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final appState = LevelUpScope.of(context);
    final now = DateTime.now();
    final days = _weekDays(appState.taskHistory, now, selectedDate);
    final doneCount = days.where((day) => day.state == DayState.done).length;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      borderRadius: 22,
      opacity: .36,
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenMonth,
            child: Row(
              children: [
                const Text('THIS WEEK', style: AppText.eyebrow),
                const Spacer(),
                Text('$doneCount of ${days.length} days', style: AppText.body),
                const SizedBox(width: 6),
                const Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final day in days)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelectDate(day.date),
                  child: Column(
                    children: [
                      WeekDayBubble(day: day),
                      const SizedBox(height: 6),
                      Text(
                        day.label,
                        style: AppText.caption.copyWith(
                          color: day.isSelected
                              ? AppColors.clay
                              : AppColors.muted,
                          fontWeight: day.isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      if (day.isToday || day.isSelected) ...[
                        const SizedBox(height: 3),
                        Container(
                          width: day.isSelected ? 18 : 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: day.isSelected
                                ? AppColors.sage
                                : AppColors.clay,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ] else
                        const SizedBox(height: 8),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<WeekDayState> _weekDays(
    List<DailyTaskHistory> history,
    DateTime now,
    DateTime selectedDate,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: today.weekday - 1));
    final byDate = {
      for (final day in history)
        DateTime(day.date.year, day.date.month, day.date.day): day,
    };
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return [
      for (var index = 0; index < 7; index++)
        _weekDayState(
          labels[index],
          start.add(Duration(days: index)),
          today,
          DateTime(selectedDate.year, selectedDate.month, selectedDate.day),
          byDate[start.add(Duration(days: index))],
        ),
    ];
  }

  WeekDayState _weekDayState(
    String label,
    DateTime date,
    DateTime today,
    DateTime selectedDate,
    DailyTaskHistory? history,
  ) {
    final isToday = _isSameDay(date, today);
    final isSelected = _isSameDay(date, selectedDate);
    final state = _dayStateFor(date, today, history);
    return WeekDayState(
      label,
      date,
      state,
      isToday: isToday,
      isSelected: isSelected,
      completedCount: history?.completedCount ?? 0,
      plannedCount: history?.plannedCount ?? 0,
    );
  }

  DayState _dayStateFor(
    DateTime date,
    DateTime today,
    DailyTaskHistory? history,
  ) {
    if (date.isAfter(today)) return DayState.future;
    if (history == null || history.plannedCount == 0) {
      return date.isBefore(today) ? DayState.future : DayState.today;
    }
    if (history.isComplete) return DayState.done;
    if (date.isBefore(today)) {
      return history.hasAnyProgress ? DayState.partial : DayState.missed;
    }
    return DayState.today;
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class LucyCoachMessage extends StatelessWidget {
  const LucyCoachMessage({
    super.key,
    required this.message,
    required this.onTap,
  });

  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -9,
                  right: 24,
                  child: Transform.rotate(
                    angle: math.pi / 4,
                    child: Container(
                      width: 18,
                      height: 18,
                      color: Colors.white.withValues(alpha: .92),
                    ),
                  ),
                ),
                GlassCard(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
                  borderRadius: 18,
                  opacity: .9,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipOval(
                        child: Image.asset(
                          'assets/images/lucy_portrait.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Lucy, your coach',
                                  style: AppText.chatName,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('"$message"', style: AppText.chatBody),
                            const SizedBox(height: 8),
                            const Text('Just now', style: AppText.tiny),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({super.key});

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: FireworkPainter(progress: _controller.value),
            );
          },
        ),
      ),
    );
  }
}

class FireworkPainter extends CustomPainter {
  FireworkPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final bursts = [
      Offset(size.width * .25, size.height * .28),
      Offset(size.width * .72, size.height * .24),
      Offset(size.width * .52, size.height * .42),
    ];
    final colors = [AppColors.clay, AppColors.sage, AppColors.gold];
    for (var burst = 0; burst < bursts.length; burst++) {
      final local = ((progress - burst * .12).clamp(0.0, 1.0));
      final radius = 10 + local * 74;
      final opacity = (1 - local).clamp(0.0, 1.0);
      for (var i = 0; i < 14; i++) {
        final angle = i * math.pi * 2 / 14;
        final start =
            bursts[burst] +
            Offset(math.cos(angle), math.sin(angle)) * (radius * .36);
        final end =
            bursts[burst] + Offset(math.cos(angle), math.sin(angle)) * radius;
        final paint = Paint()
          ..color = colors[(i + burst) % colors.length].withValues(
            alpha: opacity * .8,
          )
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(start, end, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant FireworkPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

enum DayState { done, missed, partial, today, future }

class WeekDayState {
  const WeekDayState(
    this.label,
    this.date,
    this.state, {
    this.isToday = false,
    this.isSelected = false,
    this.completedCount = 0,
    this.plannedCount = 0,
  });

  final String label;
  final DateTime date;
  final DayState state;
  final bool isToday;
  final bool isSelected;
  final int completedCount;
  final int plannedCount;
}

class WeekDayBubble extends StatelessWidget {
  const WeekDayBubble({super.key, required this.day});

  final WeekDayState day;

  @override
  Widget build(BuildContext context) {
    final border = day.isSelected
        ? Border.all(color: AppColors.sage, width: 2)
        : null;
    if (day.state == DayState.done || day.state == DayState.today) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: border,
          color: day.state == DayState.today ? AppColors.clay : AppColors.sage,
        ),
        child: Icon(
          day.state == DayState.today
              ? CupertinoIcons.circle_fill
              : CupertinoIcons.check_mark,
          size: day.state == DayState.today ? 10 : 17,
          color: Colors.white,
        ),
      );
    }
    if (day.state == DayState.missed) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: border,
          color: AppColors.clay.withValues(alpha: .12),
        ),
        child: const Icon(
          CupertinoIcons.xmark,
          size: 15,
          color: AppColors.clay,
        ),
      );
    }
    if (day.state == DayState.partial) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: border,
          color: AppColors.gold.withValues(alpha: .16),
        ),
        child: const Icon(
          CupertinoIcons.minus,
          size: 15,
          color: AppColors.gold,
        ),
      );
    }
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        color: Colors.white.withValues(alpha: .42),
      ),
      child: Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.taupe),
        ),
      ),
    );
  }
}

class MonthOverviewScreen extends StatefulWidget {
  const MonthOverviewScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<MonthOverviewScreen> createState() => _MonthOverviewScreenState();
}

class _MonthOverviewScreenState extends State<MonthOverviewScreen> {
  late DateTime _visibleMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  late DateTime _selectedDate = _dateOnly(DateTime.now());

  DateTime get _firstVisibleMonth =>
      DateTime(DateTime.now().year, DateTime.now().month);
  DateTime get _lastVisibleMonth => DateTime(2028, 12);
  bool get _canGoPrevious => _visibleMonth.isAfter(_firstVisibleMonth);
  bool get _canGoNext => _visibleMonth.isBefore(_lastVisibleMonth);

  @override
  Widget build(BuildContext context) {
    final appState = LevelUpScope.of(context);
    final now = DateTime.now();
    final days = _monthDays(
      appState.taskHistory,
      now,
      _visibleMonth,
      appState.goals,
    );
    final doneCount = days.where((day) => day.state == DayState.done).length;
    final monthName = _monthName(_visibleMonth.month);
    final selectedDay = days.firstWhere(
      (day) => _isSameDay(day.date, _selectedDate),
      orElse: () => _monthDayState(_selectedDate, _dateOnly(now), null, 0),
    );
    final selectedTasks = _tasksForDay(appState.tasks, _selectedDate, now);
    final selectedDeadlines = _deadlinesForDay(appState.goals, _selectedDate);

    return AppScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 28),
            onPressed: widget.onBack,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.chevron_left, size: 18),
                SizedBox(width: 4),
                Text('Home'),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('$monthName ${_visibleMonth.year}', style: AppText.title),
          const SizedBox(height: 6),
          const Text(
            'Your task rhythm, history and goal deadlines.',
            style: AppText.body,
          ),
          const SizedBox(height: 22),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('MONTHLY MOMENTUM', style: AppText.eyebrow),
                    const Spacer(),
                    Text(
                      '$doneCount of ${days.length}',
                      style: AppText.bodyStrong,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    GlassIconButton(
                      icon: CupertinoIcons.chevron_left,
                      onTap: _canGoPrevious ? _showPreviousMonth : null,
                    ),
                    const Spacer(),
                    GlassIconButton(
                      icon: CupertinoIcons.chevron_right,
                      onTap: _canGoNext ? _showNextMonth : null,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: days.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final day = days[index];
                    return MonthDayCell(
                      day: day,
                      selected: _isSameDay(day.date, _selectedDate),
                      onTap: () => setState(() => _selectedDate = day.date),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              LegendDot(color: AppColors.sage, label: 'Done'),
              LegendDot(color: AppColors.clay, label: 'Missed / Today'),
              LegendDot(color: AppColors.gold, label: 'Partial'),
              LegendDot(color: AppColors.taupe, label: 'Upcoming'),
              LegendDot(color: AppColors.ink, label: 'Deadline'),
            ],
          ),
          const SizedBox(height: 18),
          CalendarDayDetailCard(
            date: _selectedDate,
            day: selectedDay,
            tasks: selectedTasks,
            goals: appState.goals,
            deadlines: selectedDeadlines,
            today: _dateOnly(now),
          ),
        ],
      ),
    );
  }

  List<MonthDayState> _monthDays(
    List<DailyTaskHistory> history,
    DateTime now,
    DateTime visibleMonth,
    List<Goal> goals,
  ) {
    final today = _dateOnly(now);
    final monthStart = DateTime(visibleMonth.year, visibleMonth.month);
    final nextMonth = DateTime(visibleMonth.year, visibleMonth.month + 1);
    final dayCount = nextMonth.difference(monthStart).inDays;
    final byDate = {for (final day in history) _dateOnly(day.date): day};

    return [
      for (var day = 1; day <= dayCount; day++)
        _monthDayState(
          DateTime(visibleMonth.year, visibleMonth.month, day),
          today,
          byDate[DateTime(visibleMonth.year, visibleMonth.month, day)],
          _deadlinesForDay(
            goals,
            DateTime(visibleMonth.year, visibleMonth.month, day),
          ).length,
        ),
    ];
  }

  void _showPreviousMonth() {
    if (!_canGoPrevious) return;
    _changeVisibleMonth(DateTime(_visibleMonth.year, _visibleMonth.month - 1));
  }

  void _showNextMonth() {
    if (!_canGoNext) return;
    _changeVisibleMonth(DateTime(_visibleMonth.year, _visibleMonth.month + 1));
  }

  void _changeVisibleMonth(DateTime month) {
    setState(() {
      _visibleMonth = DateTime(month.year, month.month);
      if (!_isSameMonth(_selectedDate, _visibleMonth)) {
        _selectedDate = _visibleMonth;
      }
    });
  }

  MonthDayState _monthDayState(
    DateTime date,
    DateTime today,
    DailyTaskHistory? history,
    int deadlineCount,
  ) {
    return MonthDayState(
      _dateOnly(date),
      _dayStateFor(date, today, history),
      completedCount: history?.completedCount ?? 0,
      plannedCount: history?.plannedCount ?? 0,
      deadlineCount: deadlineCount,
    );
  }

  DayState _dayStateFor(
    DateTime date,
    DateTime today,
    DailyTaskHistory? history,
  ) {
    if (_dateOnly(date).isAfter(today)) return DayState.future;
    if (history == null || history.plannedCount == 0) {
      return _dateOnly(date).isBefore(today) ? DayState.missed : DayState.today;
    }
    if (history.isComplete) return DayState.done;
    if (_dateOnly(date).isBefore(today)) {
      return history.hasAnyProgress ? DayState.partial : DayState.missed;
    }
    return DayState.today;
  }

  List<DailyTask> _tasksForDay(
    List<DailyTask> tasks,
    DateTime selectedDate,
    DateTime now,
  ) {
    final selected = _dateOnly(selectedDate);
    final today = _dateOnly(now);
    return tasks.where((task) {
      final plannedFor = task.plannedFor;
      if (plannedFor == null) return _isSameDay(selected, today);
      return _isSameDay(plannedFor, selected);
    }).toList();
  }

  List<CalendarDeadline> _deadlinesForDay(List<Goal> goals, DateTime date) {
    final selected = _dateOnly(date);
    final deadlines = <CalendarDeadline>[];
    for (final goal in goals) {
      final goalDeadline = _parseGoalDeadline(goal.detail);
      if (goalDeadline != null && _isSameDay(goalDeadline, selected)) {
        deadlines.add(
          CalendarDeadline(
            title: goal.title,
            category: goal.category,
            type: 'Goal deadline',
          ),
        );
      }
      for (final task in goal.milestones) {
        if (task.dueDate != null && _isSameDay(task.dueDate!, selected)) {
          deadlines.add(
            CalendarDeadline(
              title: task.title,
              category: goal.category,
              type: 'Task deadline',
            ),
          );
        }
      }
    }
    return deadlines;
  }

  DateTime? _parseGoalDeadline(String detail) {
    final firstPart = detail.split('·').first.trim();
    if (firstPart.isEmpty) return null;
    final isoMatch = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(firstPart);
    if (isoMatch != null) {
      final parsed = DateTime.tryParse(isoMatch.group(0)!);
      return parsed == null ? null : _dateOnly(parsed);
    }
    final friendly = RegExp(
      r'^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2}),\s*(\d{4})$',
    ).firstMatch(firstPart);
    if (friendly == null) return null;
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    return DateTime(
      int.parse(friendly.group(3)!),
      months[friendly.group(1)!]!,
      int.parse(friendly.group(2)!),
    );
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}

class CalendarDayDetailCard extends StatelessWidget {
  const CalendarDayDetailCard({
    super.key,
    required this.date,
    required this.day,
    required this.tasks,
    required this.goals,
    required this.deadlines,
    required this.today,
  });

  final DateTime date;
  final MonthDayState day;
  final List<DailyTask> tasks;
  final List<Goal> goals;
  final List<CalendarDeadline> deadlines;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final goalById = {for (final goal in goals) goal.id: goal};
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      borderRadius: 24,
      opacity: .50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_formatDate(date), style: AppText.cardTitle),
              ),
              Text(
                '${day.completedCount}/${day.plannedCount} tasks',
                style: AppText.caption.copyWith(color: AppColors.sage),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('TASK HISTORY', style: AppText.eyebrow),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            Text(
              'No tasks planned for this day.',
              style: AppText.caption.copyWith(color: AppColors.muted),
            )
          else
            for (final task in tasks)
              _DayTaskRow(
                task: task,
                goalTitle: goalById[task.goalId]?.title,
                isPast: date.isBefore(today),
              ),
          const SizedBox(height: 14),
          const Text('DEADLINES', style: AppText.eyebrow),
          const SizedBox(height: 8),
          if (deadlines.isEmpty)
            Text(
              'No goal deadlines on this day.',
              style: AppText.caption.copyWith(color: AppColors.muted),
            )
          else
            for (final deadline in deadlines)
              _DayDeadlineRow(deadline: deadline),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _DayTaskRow extends StatelessWidget {
  const _DayTaskRow({
    required this.task,
    required this.goalTitle,
    required this.isPast,
  });

  final DailyTask task;
  final String? goalTitle;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final missed = isPast && !task.completed;
    final icon = task.completed
        ? CupertinoIcons.check_mark_circled_solid
        : missed
        ? CupertinoIcons.xmark_circle_fill
        : CupertinoIcons.circle;
    final color = task.completed
        ? AppColors.sage
        : missed
        ? AppColors.clay
        : AppColors.taupe;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: AppText.bodyStrong),
                if (goalTitle != null) ...[
                  const SizedBox(height: 2),
                  Text('Goal: $goalTitle', style: AppText.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayDeadlineRow extends StatelessWidget {
  const _DayDeadlineRow({required this.deadline});

  final CalendarDeadline deadline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(CupertinoIcons.calendar, size: 19, color: AppColors.sage),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deadline.title, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  '${deadline.type} · ${deadline.category}',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CalendarDeadline {
  const CalendarDeadline({
    required this.title,
    required this.category,
    required this.type,
  });

  final String title;
  final String category;
  final String type;
}

class MonthDayCell extends StatelessWidget {
  const MonthDayCell({
    super.key,
    required this.day,
    this.selected = false,
    this.onTap,
  });

  final MonthDayState day;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (day.state) {
      DayState.done => AppColors.sage,
      DayState.missed => AppColors.clay,
      DayState.partial => AppColors.gold,
      DayState.today => AppColors.clay,
      DayState.future => AppColors.taupe,
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: day.state == DayState.future
              ? Colors.white.withValues(alpha: .28)
              : color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: selected ? 1.8 : 1,
            color: selected
                ? AppColors.ink
                : day.state == DayState.today
                ? AppColors.clay
                : Colors.white.withValues(alpha: .58),
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                '${day.day}',
                style: AppText.tiny.copyWith(
                  color: day.state == DayState.future ? AppColors.taupe : color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (day.deadlineCount > 0)
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.ink,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MonthDayState {
  const MonthDayState(
    this.date,
    this.state, {
    this.completedCount = 0,
    this.plannedCount = 0,
    this.deadlineCount = 0,
  });

  final DateTime date;
  final DayState state;
  final int completedCount;
  final int plannedCount;
  final int deadlineCount;

  int get day => date.day;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool _isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppText.tiny),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text(title, style: AppText.section)),
        if (trailing != null)
          Text(
            trailing!,
            style: AppText.bodyStrong.copyWith(color: AppColors.sage),
          ),
      ],
    );
  }
}

class EmptyGlassState extends StatelessWidget {
  const EmptyGlassState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      borderRadius: 26,
      opacity: .42,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.sage.withValues(alpha: .82),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardTitle),
                const SizedBox(height: 4),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.icon,
    required this.tag,
    required this.title,
    required this.subtitle,
    this.done = false,
    this.onTap,
    this.onOpen,
  });

  final IconData icon;
  final String tag;
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback? onTap;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen ?? onTap,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        borderRadius: 22,
        opacity: .36,
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (done ? AppColors.sage : AppColors.clay).withValues(
                  alpha: done ? .9 : .78,
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 25),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategoryPill(label: tag),
                  const SizedBox(height: 7),
                  Text(
                    title,
                    style: AppText.cardTitle.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? AppColors.muted : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppText.caption),
                ],
              ),
            ),
            GestureDetector(
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AppColors.sage : Colors.transparent,
                  border: Border.all(
                    color: done ? AppColors.sage : AppColors.taupe,
                    width: 2,
                  ),
                ),
                child: done
                    ? const Icon(
                        CupertinoIcons.check_mark,
                        size: 17,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryPill extends StatelessWidget {
  const CategoryPill({super.key, required this.label, this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? AppColors.clay : AppColors.cream.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .6)),
      ),
      child: Text(
        label,
        style: AppText.pill.copyWith(
          color: active ? Colors.white : AppColors.muted,
        ),
      ),
    );
  }
}

class GlassSegmentedControl extends StatelessWidget {
  const GlassSegmentedControl({
    super.key,
    required this.selectedRight,
    required this.leftTitle,
    required this.leftLabel,
    required this.rightTitle,
    required this.rightLabel,
    required this.onChanged,
  });

  final bool selectedRight;
  final String leftTitle;
  final String leftLabel;
  final String rightTitle;
  final String rightLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(6),
      borderRadius: 28,
      child: Row(
        children: [
          Expanded(
            child: _SegmentTile(
              active: !selectedRight,
              title: leftTitle,
              label: leftLabel,
              onTap: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _SegmentTile(
              active: selectedRight,
              title: rightTitle,
              label: rightLabel,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.active,
    required this.title,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final String title;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: .72)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: active
                ? Colors.white.withValues(alpha: .88)
                : Colors.transparent,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: .06),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppText.bodyStrong.copyWith(
                color: active ? AppColors.sage : AppColors.muted,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? AppColors.sage.withValues(alpha: .20)
                    : AppColors.taupe.withValues(alpha: .22),
              ),
              child: Text(
                title,
                style: AppText.bodyStrong.copyWith(
                  color: active ? AppColors.sage : AppColors.muted,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.goal,
    required this.onTap,
    required this.currentTask,
    this.onStart,
    this.onTaskTap,
    this.onMore,
  });

  final Goal goal;
  final String currentTask;
  final VoidCallback onTap;
  final VoidCallback? onStart;
  final VoidCallback? onTaskTap;
  final VoidCallback? onMore;

  Color get _color {
    if (goal.completed) return AppColors.sage;
    switch (goal.category.toUpperCase()) {
      case 'CAREER':
        return AppColors.gold;
      case 'FINANCE':
        return AppColors.sage;
      default:
        return AppColors.sage;
    }
  }

  IconData get _icon {
    switch (goal.category.toUpperCase()) {
      case 'CAREER':
        return CupertinoIcons.briefcase;
      case 'FINANCE':
        return CupertinoIcons.money_dollar;
      case 'LEARNING':
        return CupertinoIcons.book;
      case 'RELATIONSHIPS':
      case 'FAMILY':
        return CupertinoIcons.person_2;
      case 'PERSONAL':
        return CupertinoIcons.sparkles;
      default:
        return CupertinoIcons.heart;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final isNotStarted = goal.status == GoalStatus.notStarted;
    final statusLabel = goal.paused
        ? 'Paused'
        : switch (goal.status) {
            GoalStatus.notStarted => 'Not started',
            GoalStatus.currentTask => 'Current task',
            GoalStatus.completed => 'Completed',
          };
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        borderRadius: 24,
        opacity: .52,
        child: Row(
          children: [
            if (goal.completed) ...[
              AchievementIllustration(icon: _icon, color: color),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategoryPill(label: goal.category),
                  const SizedBox(height: 10),
                  Text(goal.title, style: AppText.goalTitle),
                  const SizedBox(height: 5),
                  Text(goal.detail, style: AppText.caption),
                  const SizedBox(height: 12),
                  Text(
                    statusLabel,
                    style: AppText.tiny.copyWith(
                      color: isNotStarted ? AppColors.muted : color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    goal.completed
                        ? goal.vision
                        : (isNotStarted
                              ? 'Tap Start to activate this goal'
                              : currentTask),
                    style: AppText.caption.copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: 12),
                  ProgressLine(value: goal.progress, color: color),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (goal.completed)
              Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Icon(CupertinoIcons.check_mark, color: color),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Completed',
                    style: AppText.tiny.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              )
            else if (isNotStarted)
              GestureDetector(
                onTap: onStart,
                child: Column(
                  children: [
                    RingProgress(
                      progress: 0,
                      label: '0%',
                      size: 82,
                      color: color,
                      labelStyle: AppText.ringCompact,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: color.withValues(alpha: .28)),
                      ),
                      child: Text(
                        'Start',
                        style: AppText.tiny.copyWith(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              GestureDetector(
                onTap: onTaskTap,
                child: RingProgress(
                  progress: goal.progress,
                  label: '${(goal.progress * 100).round()}%',
                  size: 96,
                  color: color,
                  labelStyle: AppText.ringCompact,
                ),
              ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onMore,
              child: const Icon(
                CupertinoIcons.ellipsis_circle,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GoalJourneyCard extends StatelessWidget {
  const GoalJourneyCard({super.key});

  @override
  Widget build(BuildContext context) {
    const bars = [44.0, 62.0, 88.0, 110.0, 132.0];
    const labels = [
      'Build base',
      '5K race',
      '10K race',
      'Half prep',
      'Race day',
    ];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Goal Journey', style: AppText.section),
          const SizedBox(height: 24),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < bars.length; i++)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 40,
                        height: bars[i],
                        decoration: BoxDecoration(
                          color: i == 2
                              ? AppColors.clay
                              : i < 2
                              ? AppColors.clay.withValues(alpha: .58)
                              : AppColors.cream,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        labels[i],
                        style: AppText.tiny.copyWith(
                          color: i == 2 ? AppColors.clay : AppColors.ink,
                          fontWeight: i == 2
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(color: AppColors.hairline),
          const SizedBox(height: 8),
          const Center(
            child: Text.rich(
              TextSpan(
                text: 'Currently at ',
                children: [
                  TextSpan(
                    text: '10K race',
                    style: TextStyle(
                      color: AppColors.clay,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              style: AppText.body,
            ),
          ),
        ],
      ),
    );
  }
}

class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        PhotoTile(icon: CupertinoIcons.plus, label: 'Add photo'),
        SizedBox(width: 10),
        PhotoTile(text: '5K', label: 'Race day', color: AppColors.sage),
        SizedBox(width: 10),
        PhotoTile(text: '16K', label: 'Long run', color: AppColors.clay),
      ],
    );
  }
}

class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    this.icon,
    this.text,
    required this.label,
    this.color = AppColors.gold,
  });

  final IconData? icon;
  final String? text;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 12),
        borderRadius: 16,
        opacity: .46,
        child: Column(
          children: [
            if (icon != null)
              Icon(icon, color: AppColors.clay)
            else
              Text(text!, style: AppText.bodyStrong.copyWith(color: color)),
            const SizedBox(height: 6),
            Text(label, style: AppText.tiny),
          ],
        ),
      ),
    );
  }
}

class FutureMeCard extends StatelessWidget {
  const FutureMeCard({super.key, required this.onRegenerate});

  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/images/future_me_ella.png',
              height: 282,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 14),
          const Text('Dr. Ella Hartwell, MD', style: AppText.identity),
          const SizedBox(height: 4),
          const Text(
            'Marathon finisher · Healer · Leader',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onRegenerate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.clay.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.clay.withValues(alpha: .22),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    CupertinoIcons.wand_stars,
                    size: 16,
                    color: AppColors.clay,
                  ),
                  SizedBox(width: 8),
                  Text('Regenerate visualization', style: AppText.bodyStrong),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RegenerateStep extends StatelessWidget {
  const RegenerateStep({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 23, color: AppColors.clay),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.cardTitle),
              const SizedBox(height: 6),
              Text(body, style: AppText.body),
            ],
          ),
        ),
      ],
    );
  }
}

class GlassActionButton extends StatelessWidget {
  const GlassActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.strong = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool strong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: strong ? AppColors.clay : Colors.white.withValues(alpha: .44),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .68)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: strong ? Colors.white : AppColors.clay),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyStrong.copyWith(
                  color: strong ? Colors.white : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LifeAreasCard extends StatefulWidget {
  const LifeAreasCard({super.key, required this.onAreaTap});

  final ValueChanged<LifeAreaData> onAreaTap;

  @override
  State<LifeAreasCard> createState() => _LifeAreasCardState();
}

class _LifeAreasCardState extends State<LifeAreasCard> {
  bool _future = false;

  static const areas = [
    LifeAreaData('Health', 64, 88, ['Run a Half Marathon', 'Workout · 30 min']),
    LifeAreaData('Finance', 45, 72, ['Buy a House', 'Move £25 to savings']),
    LifeAreaData('Career', 58, 84, ['Become a Doctor', 'Study MCAT notes']),
    LifeAreaData('Personal', 52, 76, ['Read 12 Books', 'Call mum']),
    LifeAreaData('Family', 49, 70, ['Sunday family dinner']),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Life Areas', style: AppText.lifeAreaTitle),
              const Spacer(),
              Text(
                'Tap area to explore',
                style: AppText.tiny.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 188,
            child: RadarChart(
              showFuture: _future,
              areas: areas,
              onAreaTap: widget.onAreaTap,
            ),
          ),
          const SizedBox(height: 10),
          NowFutureToggle(
            future: _future,
            onChanged: (value) => setState(() => _future = value),
          ),
        ],
      ),
    );
  }
}

class RadarChart extends StatelessWidget {
  const RadarChart({
    super.key,
    required this.showFuture,
    required this.areas,
    required this.onAreaTap,
  });

  final bool showFuture;
  final List<LifeAreaData> areas;
  final ValueChanged<LifeAreaData> onAreaTap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: RadarPainter(showFuture: showFuture),
      child: Stack(
        children: [
          Positioned(
            top: 4,
            left: 0,
            right: 0,
            child: Center(
              child: _AreaLabel(area: areas[0], onTap: onAreaTap),
            ),
          ),
          Positioned(
            top: 74,
            right: 4,
            child: _AreaLabel(area: areas[1], onTap: onAreaTap),
          ),
          Positioned(
            bottom: 4,
            right: 34,
            child: _AreaLabel(area: areas[2], onTap: onAreaTap),
          ),
          Positioned(
            bottom: 4,
            left: 24,
            child: _AreaLabel(area: areas[3], onTap: onAreaTap),
          ),
          Positioned(
            top: 74,
            left: 4,
            child: _AreaLabel(area: areas[4], onTap: onAreaTap),
          ),
        ],
      ),
    );
  }
}

class _AreaLabel extends StatelessWidget {
  const _AreaLabel({required this.area, required this.onTap});

  final LifeAreaData area;
  final ValueChanged<LifeAreaData> onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(area),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(
          area.name,
          style: AppText.tiny.copyWith(
            color: AppColors.clay,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  RadarPainter({required this.showFuture});

  final bool showFuture;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 5);
    final radius = math.min(size.width, size.height) * .34;
    final axes = List.generate(5, (i) {
      final angle = -math.pi / 2 + i * math.pi * 2 / 5;
      return Offset(math.cos(angle), math.sin(angle));
    });

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.hairline;
    for (final scale in [.34, .66, 1.0]) {
      canvas.drawPath(
        _polygon(center, axes, List.filled(5, radius * scale)),
        gridPaint,
      );
    }
    for (final axis in axes) {
      canvas.drawLine(center, center + axis * radius, gridPaint);
    }

    final future = _polygon(
      center,
      axes,
      [66, 59, 61, 60, 56].map((v) => radius * v / 72).toList(),
    );
    final current = _polygon(
      center,
      axes,
      [46, 40, 50, 43, 42].map((v) => radius * v / 72).toList(),
    );
    final activePath = showFuture ? future : current;
    final activeColor = showFuture ? AppColors.sage : AppColors.clay;
    final referencePath = showFuture ? current : future;
    final referenceColor = showFuture ? AppColors.clay : AppColors.sage;

    canvas.drawPath(
      referencePath,
      Paint()..color = referenceColor.withValues(alpha: .07),
    );
    canvas.drawPath(
      referencePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = referenceColor.withValues(alpha: .38),
    );
    canvas.drawPath(
      activePath,
      Paint()..color = activeColor.withValues(alpha: .16),
    );
    canvas.drawPath(
      activePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeJoin = StrokeJoin.round
        ..color = activeColor,
    );
  }

  Path _polygon(Offset center, List<Offset> axes, List<double> values) {
    final path = Path();
    for (var i = 0; i < axes.length; i++) {
      final point = center + axes[i] * values[i];
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return oldDelegate.showFuture != showFuture;
  }
}

class LegendSwatch extends StatelessWidget {
  const LegendSwatch({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppText.tiny.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class NowFutureToggle extends StatelessWidget {
  const NowFutureToggle({
    super.key,
    required this.future,
    required this.onChanged,
  });

  final bool future;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .68)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TimeToggleOption(
              label: 'Now',
              active: !future,
              color: AppColors.clay,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _TimeToggleOption(
              label: 'Future',
              active: future,
              color: AppColors.sage,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeToggleOption extends StatelessWidget {
  const _TimeToggleOption({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: .16) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppText.bodyStrong.copyWith(
            color: active ? color : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

class TimeSliderMock extends StatelessWidget {
  const TimeSliderMock({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Progress through time', style: AppText.tiny),
        const SizedBox(height: 10),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const Positioned(
              left: 0,
              top: -4,
              child: _SliderDot(color: AppColors.taupe),
            ),
            const Positioned(left: 126, top: -9, child: _SliderHandle()),
            const Positioned(
              right: 0,
              top: -4,
              child: _SliderDot(color: AppColors.sage),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Past', style: AppText.tiny),
            Text('Now', style: AppText.tiny),
            Text('Future', style: AppText.tiny),
          ],
        ),
      ],
    );
  }
}

class _SliderDot extends StatelessWidget {
  const _SliderDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(radius: 6, backgroundColor: color);
  }
}

class _SliderHandle extends StatelessWidget {
  const _SliderHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.clay, width: 2),
      ),
      child: Center(
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: AppColors.clay,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class VisionChips extends StatelessWidget {
  const VisionChips({
    super.key,
    required this.visions,
    required this.selectedVisionIds,
    required this.onSelect,
  });

  final List<VisionData> visions;
  final Set<String> selectedVisionIds;
  final ValueChanged<VisionData> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 9,
      runSpacing: 10,
      children: [
        for (final vision in visions)
          GestureDetector(
            onTap: () => onSelect(vision),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selectedVisionIds.contains(vision.id)
                    ? AppColors.clay
                    : AppColors.cream.withValues(alpha: .76),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selectedVisionIds.contains(vision.id)
                      ? AppColors.clay
                      : Colors.white.withValues(alpha: .68),
                ),
              ),
              child: Text(
                vision.title,
                style: AppText.pill.copyWith(
                  color: selectedVisionIds.contains(vision.id)
                      ? Colors.white
                      : AppColors.muted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class VisionGoalsCard extends StatelessWidget {
  const VisionGoalsCard({super.key, required this.visions});

  final List<VisionData> visions;

  @override
  Widget build(BuildContext context) {
    final goals = [
      for (final vision in visions)
        for (final goal in vision.goals) goal,
    ];

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      borderRadius: 20,
      opacity: .48,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            visions.isEmpty
                ? 'Choose one or more visions'
                : '${visions.length} selected vision${visions.length == 1 ? '' : 's'} are built from',
            style: AppText.caption.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (goals.isEmpty)
            const Text(
              'Tap a vision chip above to reveal the goals behind it.',
              style: AppText.caption,
            )
          else
            for (final goal in goals.take(4)) ...[
              VisionGoalRow(goal: goal),
              if (goal != goals.take(4).last) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class VisionGoalRow extends StatelessWidget {
  const VisionGoalRow({super.key, required this.goal});

  final VisionGoalData goal;

  @override
  Widget build(BuildContext context) {
    final completed = goal.progress >= 1;
    final color = completed ? AppColors.sage : AppColors.clay;
    return Row(
      children: [
        RingProgress(
          progress: goal.progress,
          label: '${(goal.progress * 100).round()}%',
          size: 46,
          color: color,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(goal.title, style: AppText.bodyStrong),
              const SizedBox(height: 3),
              Text(goal.subtitle, style: AppText.caption),
            ],
          ),
        ),
      ],
    );
  }
}

class VisionTimelineCard extends StatelessWidget {
  const VisionTimelineCard({super.key, required this.visions});

  final List<VisionData> visions;

  @override
  Widget build(BuildContext context) {
    final milestones = [
      for (final vision in visions)
        for (final milestone in vision.milestones) milestone,
    ]..sort((a, b) => a.order.compareTo(b.order));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Goal Timeline', style: AppText.section),
        const SizedBox(height: 14),
        if (milestones.isEmpty)
          const GlassCard(
            padding: EdgeInsets.all(16),
            child: Text(
              'Select a vision to generate its goals.',
              style: AppText.caption,
            ),
          )
        else
          Stack(
            children: [
              Positioned(
                left: 10,
                top: 18,
                bottom: 18,
                child: Container(width: 2, color: AppColors.hairline),
              ),
              Column(
                children: [
                  for (final milestone in milestones) ...[
                    VisionMilestoneRow(milestone: milestone),
                    if (milestone != milestones.last)
                      const SizedBox(height: 12),
                  ],
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class VisionMilestoneRow extends StatelessWidget {
  const VisionMilestoneRow({super.key, required this.milestone});

  final VisionMilestoneData milestone;

  @override
  Widget build(BuildContext context) {
    final isDone = milestone.stage == VisionStage.done;
    final isNow = milestone.stage == VisionStage.now;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(
            color: isNow ? AppColors.clay : AppColors.background,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDone
                  ? AppColors.sage
                  : isNow
                  ? AppColors.clay
                  : AppColors.taupe,
              width: 2,
            ),
          ),
          child: isNow
              ? Center(
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            borderRadius: 20,
            opacity: isNow ? .62 : .46,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  milestone.date,
                  style: AppText.eyebrow.copyWith(
                    color: isNow ? AppColors.clay : AppColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  milestone.title,
                  style: AppText.timelineTitle.copyWith(
                    color: isDone ? AppColors.muted : AppColors.ink,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (isNow) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.clay.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'In progress',
                      style: AppText.tiny.copyWith(
                        color: AppColors.clay,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ReflectionCard extends StatelessWidget {
  const ReflectionCard({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TODAY’S REFLECTION', style: AppText.eyebrow),
          const SizedBox(height: 12),
          const Text('What moved you forward today?', style: AppText.cardTitle),
          const SizedBox(height: 12),
          const Text(
            'Write one honest note. Wins count. Friction counts too.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          CupertinoTextField(
            controller: controller,
            minLines: 4,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: appTextInputFormatters,
            padding: const EdgeInsets.all(14),
            placeholder: 'Today I showed up by...',
            placeholderStyle: AppText.caption,
            style: AppText.bodyStrong,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .48),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .7)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap: () => _showReflectionHistory(context),
                child: const CategoryPill(label: 'Reflection history'),
              ),
              const Spacer(),
              const CategoryPill(label: 'Save reflection  →'),
            ],
          ),
        ],
      ),
    );
  }

  void _showReflectionHistory(BuildContext context) {
    const states = [
      DayState.done,
      DayState.done,
      DayState.missed,
      DayState.done,
      DayState.today,
      DayState.future,
      DayState.future,
      DayState.done,
      DayState.done,
      DayState.done,
      DayState.missed,
      DayState.done,
      DayState.future,
      DayState.future,
    ];
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
        child: GlassCard(
          borderRadius: 28,
          opacity: .86,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Reflection History', style: AppText.section),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Icon(CupertinoIcons.xmark_circle_fill),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap a day to revisit what you wrote.',
                style: AppText.caption,
              ),
              const SizedBox(height: 18),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: states.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemBuilder: (context, index) => MonthDayCell(
                  day: MonthDayState(
                    DateTime(
                      DateTime.now().year,
                      DateTime.now().month,
                      index + 1,
                    ),
                    states[index],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DailyQuoteCard extends StatelessWidget {
  const DailyQuoteCard({super.key, required this.quote});

  final String quote;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        /*children: [
          Text(
            'Quote of the day',
            style: AppText.section.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            quote,
            style: AppText.section.copyWith(
              fontSize: 14,
              height: 1.28,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],*/
      ),
    );
  }
}

class SoftMountainsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()..color = AppColors.sage.withValues(alpha: .10);
    final p2 = Paint()..color = AppColors.sage.withValues(alpha: .18);
    final path1 = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * .25, size.height * .52)
      ..lineTo(size.width * .50, size.height * .72)
      ..lineTo(size.width * .78, size.height * .28)
      ..lineTo(size.width, size.height * .48)
      ..lineTo(size.width, size.height)
      ..close();
    final path2 = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * .36, size.height * .70)
      ..lineTo(size.width * .62, size.height * .46)
      ..lineTo(size.width, size.height * .55)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path1, p1);
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LucyVideoCard extends StatelessWidget {
  const LucyVideoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: SizedBox(
        height: 520,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/lucy_portrait.png', fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .08),
                    Colors.black.withValues(alpha: .18),
                    Colors.black.withValues(alpha: .72),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 18,
              top: 18,
              child: CategoryPill(label: 'MINDSET'),
            ),
            Positioned(
              right: 14,
              bottom: 116,
              child: Column(
                children: const [
                  ReelAction(icon: CupertinoIcons.heart, label: '2.4k'),
                  SizedBox(height: 18),
                  ReelAction(icon: CupertinoIcons.chat_bubble, label: '118'),
                ],
              ),
            ),
            const Positioned.fill(
              child: Center(
                child: CircleAvatar(
                  radius: 31,
                  backgroundColor: Colors.white30,
                  child: Icon(
                    CupertinoIcons.play_fill,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 18,
              right: 72,
              bottom: 26,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@lucyhartwell', style: AppText.videoMeta),
                  SizedBox(height: 8),
                  Text(
                    'Your Identity is Your Destiny',
                    style: AppText.videoTitle,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'One direct reminder for the version of you you are becoming.',
                    style: AppText.videoMeta,
                  ),
                  SizedBox(height: 12),
                  ProgressLine(value: .35, color: AppColors.clay),
                ],
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .22),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .22),
                      ),
                    ),
                    child: const Text('8:24', style: AppText.videoMeta),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReelAction extends StatelessWidget {
  const ReelAction({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .22),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: .24)),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(label, style: AppText.videoMeta.copyWith(fontSize: 10)),
      ],
    );
  }
}

class EpisodeRow extends StatelessWidget {
  const EpisodeRow({
    super.key,
    required this.title,
    required this.meta,
    required this.tag,
  });

  final String title;
  final String meta;
  final String tag;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(10),
        borderRadius: 16,
        opacity: .5,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(
                    'assets/images/lucy_portrait.png',
                    width: 54,
                    height: 84,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    width: 54,
                    height: 84,
                    color: Colors.black.withValues(alpha: .18),
                  ),
                  Positioned(
                    left: 0,
                    right: 16,
                    bottom: 0,
                    child: Container(height: 3, color: AppColors.clay),
                  ),
                  const Icon(
                    CupertinoIcons.play_fill,
                    color: Colors.white,
                    size: 15,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyStrong),
                  const SizedBox(height: 4),
                  Text(meta, style: AppText.caption),
                ],
              ),
            ),
            CategoryPill(label: tag),
          ],
        ),
      ),
    );
  }
}

class DailyTaskData {
  DailyTaskData({
    required this.icon,
    required this.tag,
    required this.title,
    required this.subtitle,
    this.completed = false,
  });

  final IconData icon;
  final String tag;
  final String title;
  final String subtitle;
  bool completed;
}

class LifeAreaData {
  const LifeAreaData(this.name, this.current, this.future, this.goals);

  final String name;
  final int current;
  final int future;
  final List<String> goals;
}

class GoalData {
  const GoalData(
    this.category,
    this.title,
    this.subtitle,
    this.progress, {
    this.vision,
    this.timeline,
  });

  factory GoalData.fromGoal(Goal goal) {
    return GoalData(
      goal.category,
      goal.title,
      goal.detail,
      goal.progress,
      vision: goal.vision,
      timeline: goal.timeline,
    );
  }

  final String category;
  final String title;
  final String subtitle;
  final double progress;
  final String? vision;
  final String? timeline;
}

class VisionData {
  const VisionData({
    required this.id,
    required this.title,
    required this.selected,
    required this.goals,
    required this.milestones,
  });

  final String id;
  final String title;
  final bool selected;
  final List<VisionGoalData> goals;
  final List<VisionMilestoneData> milestones;
}

class VisionGoalData {
  const VisionGoalData(this.title, this.subtitle, this.progress);

  final String title;
  final String subtitle;
  final double progress;
}

class VisionMilestoneData {
  const VisionMilestoneData(this.order, this.date, this.title, this.stage);

  final int order;
  final String date;
  final String title;
  final VisionStage stage;
}

enum VisionStage { done, now, future }

abstract final class AppColors {
  static const background = Color(0xFFF2EEE8);
  static const ink = Color(0xFF11100E);
  static const muted = Color(0xFF66615C);
  static const clay = Color(0xFFB76752);
  static const sage = Color(0xFF75896B);
  static const taupe = Color(0xFFBDB8B2);
  static const cream = Color(0xFFECE7E0);
  static const hairline = Color(0xFFE7E2DC);
  static const gold = Color(0xFFD69B32);
}

abstract final class AppText {
  static const serif = 'LibreBaskerville';

  static const logo = TextStyle(
    fontFamily: serif,
    fontSize: 25,
    height: 1,
    fontWeight: FontWeight.w700,
    fontStyle: FontStyle.italic,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const hero = TextStyle(
    fontFamily: serif,
    fontSize: 26,
    height: 1.12,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const title = TextStyle(
    fontFamily: serif,
    fontSize: 32,
    height: 1.05,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const section = TextStyle(
    fontFamily: serif,
    fontSize: 18,
    height: 1.1,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const identity = TextStyle(
    fontFamily: serif,
    fontSize: 23,
    height: 1.1,
    fontWeight: FontWeight.w600,
    fontStyle: FontStyle.italic,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const metric = TextStyle(
    fontFamily: serif,
    fontSize: 26,
    height: .95,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
    letterSpacing: -1,
  );

  static const metricSmall = TextStyle(
    fontSize: 25,
    height: 1,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const taskDone = TextStyle(
    fontSize: 16,
    height: 1.18,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
    letterSpacing: 0,
  );

  static const ring = TextStyle(
    fontFamily: serif,
    fontSize: 28,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const ringCompact = TextStyle(
    fontSize: 13,
    height: 1,
    fontWeight: FontWeight.w900,
    color: AppColors.clay,
    letterSpacing: 0,
  );

  static const cardTitle = TextStyle(
    fontSize: 16,
    height: 1.15,
    fontWeight: FontWeight.w300,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const timelineTitle = TextStyle(
    fontSize: 18,
    height: 1.18,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const lifeAreaTitle = TextStyle(
    fontFamily: serif,
    fontSize: 18,
    height: 1.05,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const goalTitle = TextStyle(
    fontFamily: serif,
    fontSize: 22,
    height: 1.05,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const body = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
    letterSpacing: 0,
  );

  static const bodyStrong = TextStyle(
    fontSize: 14,
    height: 1.25,
    fontWeight: FontWeight.w300,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const chatName = TextStyle(
    fontSize: 12,
    height: 1.1,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const chatBody = TextStyle(
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const caption = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w300,
    color: AppColors.muted,
    letterSpacing: 0,
  );

  static const eyebrow = TextStyle(
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.8,
    color: AppColors.muted,
  );

  static const pill = TextStyle(
    fontSize: 11,
    height: 1,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
    letterSpacing: .5,
  );

  static const tiny = TextStyle(
    fontSize: 9,
    height: 1.1,
    fontWeight: FontWeight.w700,
    color: AppColors.muted,
    letterSpacing: 0,
  );

  static const statValue = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
    letterSpacing: 0,
  );

  static const videoTitle = TextStyle(
    fontFamily: serif,
    fontSize: 24,
    height: 1.05,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0,
  );

  static const videoTitleSmall = TextStyle(
    fontFamily: serif,
    fontSize: 18,
    height: 1.08,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0,
  );

  static const videoMeta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0,
  );
}
