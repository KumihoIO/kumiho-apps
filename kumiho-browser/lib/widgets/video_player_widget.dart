// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../core/utils/media_source.dart';
import '../models/models.dart';
import '../theme/kumiho_theme.dart';

/// Shows a fullscreen video player overlay for the given media item.
void showVideoPlayer(
  BuildContext context,
  MediaItem item, {
  List<MediaItem>? items,
  void Function(MediaItem)? onNavigate,
}) {
  showDialog(
    context: context,
    barrierColor: Colors.black,
    barrierDismissible: false,
    builder: (context) => VideoPlayerOverlay(
      item: item,
      items: items,
      onNavigate: onNavigate,
    ),
  );
}

/// Fullscreen video player overlay with controls
class VideoPlayerOverlay extends StatefulWidget {
  final MediaItem item;
  final List<MediaItem>? items;
  final void Function(MediaItem)? onNavigate;

  const VideoPlayerOverlay({
    super.key,
    required this.item,
    this.items,
    this.onNavigate,
  });

  @override
  State<VideoPlayerOverlay> createState() => _VideoPlayerOverlayState();
}

class _VideoPlayerOverlayState extends State<VideoPlayerOverlay> {
  late MediaItem _currentItem;
  Player? _player;
  VideoController? _videoController;
  final FocusNode _focusNode = FocusNode();
  Key _videoKey = UniqueKey(); // Force Video widget recreation
  
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isHovering = false;
  bool _isInitialized = false;
  bool _hasBuilt = false;
  
  // Playback state
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  double _volume = 1.0;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    
    // Request focus for keyboard input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _startHideControlsTimer();
    });
  }

  void _initPlayer() {
    // Create fresh player and controller
    _player = Player();
    _videoController = VideoController(_player!);
    
    // Listen to player state
    _player!.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    
    _player!.stream.position.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    
    _player!.stream.duration.listen((duration) {
      if (mounted) {
        setState(() => _duration = duration);
      }
    });
    
    _player!.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });
    
    _player!.stream.volume.listen((volume) {
      if (mounted) setState(() => _volume = volume / 100);
    });
    
    // Listen for video dimensions - mark ready when we have them
    _player!.stream.width.listen((width) {
      if (mounted && width != null && width > 0 && !_isInitialized) {
        _isInitialized = true;
        setState(() {});
        
        // After showing the Video widget, wait a frame then seek to force render
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _player?.seek(Duration.zero);
          if (_player != null && !_player!.state.playing) {
            await _player!.play();
          }
        });
      }
    });
  }

  void _loadVideo() async {
    _isInitialized = false;
    final path = _currentItem.location ?? _currentItem.thumbnailPath;
    if (path != null) {
      // Ensure media_kit is initialized before any Player/VideoController is created.
      // This must run on the main isolate.
      try {
        MediaKit.ensureInitialized();
      } catch (_) {
        // Best-effort; video will fail gracefully if missing native deps.
      }

      // Warmup cycle - needed on Windows for first playback
      final warmupPlayer = Player();
      VideoController(warmupPlayer);
      await Future.delayed(const Duration(milliseconds: 50));
      await warmupPlayer.dispose();
      
      // Create fresh player
      _initPlayer();
      
      // Generate new key to force Video widget recreation
      _videoKey = UniqueKey();
      
      // Trigger rebuild so Video widget gets the new controller
      setState(() {});
      
      // Open the media
      final src = normalizeMediaSource(path);
      try {
        await _player!.open(Media(src), play: true);
      } catch (e, st) {
        debugPrint('VideoPlayerOverlay: open failed src=$src err=$e');
        debugPrintStack(stackTrace: st);
      }
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _player?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isHovering && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onMouseMove() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideControlsTimer();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        break;
      case LogicalKeyboardKey.space:
        _togglePlayPause();
        break;
      case LogicalKeyboardKey.arrowLeft:
        _seekRelative(-10);
        break;
      case LogicalKeyboardKey.arrowRight:
        _seekRelative(10);
        break;
      case LogicalKeyboardKey.arrowUp:
        _adjustVolume(0.1);
        break;
      case LogicalKeyboardKey.arrowDown:
        _adjustVolume(-0.1);
        break;
      case LogicalKeyboardKey.keyM:
        _toggleMute();
        break;
      case LogicalKeyboardKey.keyF:
        // Already fullscreen
        break;
      case LogicalKeyboardKey.home:
        _player?.seek(Duration.zero);
        break;
      case LogicalKeyboardKey.end:
        if (_duration.inSeconds > 0) {
          _player?.seek(_duration - const Duration(seconds: 1));
        }
        break;
      case LogicalKeyboardKey.pageUp:
        _navigatePrevious();
        break;
      case LogicalKeyboardKey.pageDown:
        _navigateNext();
        break;
    }
  }

  void _togglePlayPause() {
    _player?.playOrPause();
    _showControls = true;
    _startHideControlsTimer();
  }

  void _seekRelative(int seconds) {
    final newPosition = _position + Duration(seconds: seconds);
    _player?.seek(Duration(
      milliseconds: newPosition.inMilliseconds.clamp(0, _duration.inMilliseconds),
    ));
  }

  void _adjustVolume(double delta) {
    final newVolume = (_volume + delta).clamp(0.0, 1.0);
    _player?.setVolume(newVolume * 100);
    setState(() {
      _volume = newVolume;
      _isMuted = newVolume == 0;
    });
  }

  void _toggleMute() {
    if (_isMuted) {
      _player?.setVolume(_volume * 100);
      setState(() => _isMuted = false);
    } else {
      _player?.setVolume(0);
      setState(() => _isMuted = true);
    }
  }

  void _navigatePrevious() {
    if (widget.items == null || widget.items!.length <= 1) return;
    final videos = widget.items!.where((i) => i.isVideo).toList();
    final currentIndex = videos.indexWhere((i) => i.id == _currentItem.id);
    if (currentIndex > 0) {
      _switchToItem(videos[currentIndex - 1]);
    }
  }

  void _navigateNext() {
    if (widget.items == null || widget.items!.length <= 1) return;
    final videos = widget.items!.where((i) => i.isVideo).toList();
    final currentIndex = videos.indexWhere((i) => i.id == _currentItem.id);
    if (currentIndex < videos.length - 1) {
      _switchToItem(videos[currentIndex + 1]);
    }
  }

  void _switchToItem(MediaItem item) {
    setState(() {
      _currentItem = item;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    _loadVideo();
    widget.onNavigate?.call(item);
  }

  int get _currentIndex {
    if (widget.items == null) return 0;
    final videos = widget.items!.where((i) => i.isVideo).toList();
    return videos.indexWhere((i) => i.id == _currentItem.id);
  }

  int get _totalVideos {
    if (widget.items == null) return 1;
    return widget.items!.where((i) => i.isVideo).length;
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Load video after the Video widget has been built for the first time
    if (!_hasBuilt) {
      _hasBuilt = true;
      // Schedule video loading for after TWO frames to ensure Video widget is fully ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadVideo();
        });
      });
    }
    
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        onHover: (_) => _onMouseMove(),
        child: GestureDetector(
          onTap: _togglePlayPause,
          onDoubleTap: () => Navigator.of(context).pop(),
          child: Stack(
            children: [
              // Video (show placeholder if controller not ready)
              Positioned.fill(
                child: _videoController != null
                    ? Video(
                        key: _videoKey,
                        controller: _videoController!,
                        controls: NoVideoControls,
                      )
                    : const Center(
                        child: CircularProgressIndicator(
                          color: KumihoTheme.primary,
                        ),
                      ),
              ),
              
              // Buffering indicator
              if (_isBuffering)
                const Center(
                  child: CircularProgressIndicator(
                    color: KumihoTheme.primary,
                  ),
                ),
              
              // Controls overlay
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Stack(
                  children: [
                    // Top bar
                    _buildTopBar(),
                    // Center play/pause
                    if (!_isPlaying || _showControls)
                      Center(
                        child: _buildCenterPlayButton(),
                      ),
                    // Bottom controls
                    _buildBottomControls(),
                    // Navigation arrows
                    if (_totalVideos > 1) ...[
                      _buildNavigationArrow(
                        left: true,
                        enabled: _currentIndex > 0,
                        onTap: _navigatePrevious,
                      ),
                      _buildNavigationArrow(
                        left: false,
                        enabled: _currentIndex < _totalVideos - 1,
                        onTap: _navigateNext,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withAlpha(179),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentItem.name,
                    style: const TextStyle(
                      color: KumihoTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        _currentItem.artifactName,
                        style: const TextStyle(
                          color: KumihoTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: KumihoTheme.primary.withAlpha(51),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _currentItem.revision,
                          style: const TextStyle(
                            color: KumihoTheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: KumihoTheme.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close (Esc)',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPlayButton() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(128),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _isPlaying ? Icons.pause : Icons.play_arrow,
        color: Colors.white,
        size: 48,
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withAlpha(179),
                Colors.transparent,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: KumihoTheme.primary,
                  inactiveTrackColor: Colors.white.withAlpha(77),
                  thumbColor: KumihoTheme.primary,
                  overlayColor: KumihoTheme.primary.withAlpha(77),
                ),
                child: Slider(
                  value: _duration.inMilliseconds > 0
                      ? _position.inMilliseconds / _duration.inMilliseconds
                      : 0,
                  onChanged: (value) {
                    final newPosition = Duration(
                      milliseconds: (value * _duration.inMilliseconds).toInt(),
                    );
                    _player?.seek(newPosition);
                  },
                ),
              ),
              const SizedBox(height: 4),
              // Controls row
              Row(
                children: [
                  // Play/Pause
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: _togglePlayPause,
                    tooltip: _isPlaying ? 'Pause (Space)' : 'Play (Space)',
                  ),
                  // Time display
                  Text(
                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                    style: const TextStyle(
                      color: KumihoTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  // Volume
                  IconButton(
                    icon: Icon(
                      _isMuted || _volume == 0
                          ? Icons.volume_off
                          : _volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: _toggleMute,
                    tooltip: 'Mute (M)',
                  ),
                  SizedBox(
                    width: 100,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withAlpha(77),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withAlpha(77),
                      ),
                      child: Slider(
                        value: _isMuted ? 0 : _volume,
                        onChanged: (value) {
                          _player?.setVolume(value * 100);
                          setState(() {
                            _volume = value;
                            _isMuted = value == 0;
                          });
                        },
                      ),
                    ),
                  ),
                  // Video counter
                  if (_totalVideos > 1) ...[
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: KumihoTheme.backgroundCard,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / $_totalVideos',
                        style: const TextStyle(
                          color: KumihoTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationArrow({
    required bool left,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Positioned(
      left: left ? 16 : null,
      right: left ? null : 16,
      top: 0,
      bottom: 0,
      child: Center(
        child: Tooltip(
          message: left ? 'Previous video (PageUp)' : 'Next video (PageDown)',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: enabled
                      ? KumihoTheme.backgroundCard.withAlpha(204)
                      : KumihoTheme.backgroundCard.withAlpha(77),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  left ? Icons.chevron_left : Icons.chevron_right,
                  size: 32,
                  color: enabled ? KumihoTheme.textPrimary : KumihoTheme.textDimmed,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Embeddable video player widget for use within other containers (like ImageViewerOverlay)
class VideoPlayerWidget extends StatefulWidget {
  final String source;
  final bool autoPlay;
  final void Function(bool)? onFullscreenToggle;
  
  const VideoPlayerWidget({
    super.key,
    required this.source,
    this.autoPlay = false,
    this.onFullscreenToggle,
  });

  @override
  State<VideoPlayerWidget> createState() => VideoPlayerWidgetState();
}

class VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  Player? _player;
  VideoController? _videoController;
  
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isHovering = false;
  bool _isReady = false;
  
  // Playback state
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  double _volume = 1.0;
  double _volumeBeforeMute = 1.0; // Store volume before muting
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    
    // Do a warmup cycle then initialize the real player
    _warmupAndInit();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startHideControlsTimer();
    });
  }
  
  Future<void> _warmupAndInit() async {
    // media_kit must be initialized (platform channels) before creating any Player.
    // If this fails on Windows, playback and screenshots will not work.
    try {
      MediaKit.ensureInitialized();
    } catch (e, st) {
      debugPrint('MediaKit.ensureInitialized FAILED in VideoPlayerWidget: $e');
      debugPrintStack(stackTrace: st);
      return;
    }

    // Create a dummy player and controller to trigger the VideoOutput creation
    // This is needed on Windows because media_kit requires a full create/destroy cycle
    final warmupPlayer = Player();
    VideoController(warmupPlayer);
    
    // Wait a bit for it to initialize
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Dispose to trigger the destructor cycle
    await warmupPlayer.dispose();
    
    // Now create the real player
    _player = Player();
    _videoController = VideoController(_player!);
    
    // Listen to player state
    _player!.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    
    _player!.stream.position.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    
    _player!.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    
    _player!.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });
    
    _player!.stream.volume.listen((volume) {
      if (mounted) setState(() => _volume = volume / 100);
    });
    
    // Listen for video dimensions - mark ready when we have them
    _player!.stream.width.listen((width) {
      if (mounted && width != null && width > 0 && !_isReady) {
        _isReady = true;
        setState(() {});
        
        // After showing the Video widget, wait a frame then seek to force render
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _player?.seek(Duration.zero);
          if (widget.autoPlay && _player != null && !_player!.state.playing) {
            await _player!.play();
          }
        });
      }
    });
    
    // Open the media (don't mark ready yet - wait for dimensions)
    final src = normalizeMediaSource(widget.source);
    try {
      await _player!.open(Media(src), play: widget.autoPlay);
    } catch (e, st) {
      debugPrint('VideoPlayerWidget: open failed src=$src err=$e');
      debugPrintStack(stackTrace: st);
    }
  }

  void _loadVideo() async {
    if (_player == null) return;
    _isReady = false;
    try {
      MediaKit.ensureInitialized();
    } catch (e, st) {
      debugPrint('MediaKit.ensureInitialized FAILED in VideoPlayerWidget._loadVideo: $e');
      debugPrintStack(stackTrace: st);
      return;
    }
    final src = normalizeMediaSource(widget.source);
    try {
      await _player!.open(Media(src), play: widget.autoPlay);
    } catch (e, st) {
      debugPrint('VideoPlayerWidget: open failed src=$src err=$e');
      debugPrintStack(stackTrace: st);
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _loadVideo();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isHovering && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onMouseMove() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideControlsTimer();
  }

  /// Toggle play/pause state - can be called externally via GlobalKey
  void togglePlayPause() {
    _player?.playOrPause();
  }

  /// Toggle mute state - can be called externally via GlobalKey
  void toggleMute() {
    setState(() {
      if (!_isMuted) {
        // Muting: save current volume before muting
        _volumeBeforeMute = _volume > 0 ? _volume : 1.0;
        _isMuted = true;
        _player?.setVolume(0);
      } else {
        // Unmuting: restore previous volume
        _isMuted = false;
        _player?.setVolume(_volumeBeforeMute * 100);
      }
    });
  }

  void _seekRelative(int seconds) {
    final newPosition = _position + Duration(seconds: seconds);
    final clampedPosition = newPosition.isNegative
        ? Duration.zero
        : (newPosition > _duration ? _duration : newPosition);
    _player?.seek(clampedPosition);
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Use ExcludeFocus to prevent video controls from stealing keyboard focus
    // This allows the parent ImageViewer to handle keyboard events
    return ExcludeFocus(
      child: MouseRegion(
        onEnter: (_) {
          _isHovering = true;
          setState(() => _showControls = true);
        },
        onExit: (_) {
          _isHovering = false;
          _startHideControlsTimer();
        },
        onHover: (_) => _onMouseMove(),
        child: GestureDetector(
          onTap: togglePlayPause,
          child: Stack(
            children: [
              // Video display (show loading indicator until ready)
              Center(
                child: _isReady && _videoController != null
                    ? Video(
                        controller: _videoController!,
                        fit: BoxFit.contain,
                      )
                    : const CircularProgressIndicator(
                        color: KumihoTheme.primary,
                      ),
              ),
              
              // Buffering indicator
              if (_isBuffering && _isReady)
                const Center(
                  child: CircularProgressIndicator(
                    color: KumihoTheme.primary,
                  ),
                ),
              
              // Controls overlay
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _buildControls(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.transparent,
              Colors.black.withAlpha(179),
            ],
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(
                      color: KumihoTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: _duration.inMilliseconds > 0
                            ? _position.inMilliseconds / _duration.inMilliseconds
                            : 0,
                        onChanged: (value) {
                          final newPosition = Duration(
                            milliseconds: (value * _duration.inMilliseconds).round(),
                          );
                          _player?.seek(newPosition);
                        },
                        activeColor: KumihoTheme.primary,
                        inactiveColor: KumihoTheme.textDimmed,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(
                      color: KumihoTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            
            // Control buttons
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Rewind
                  IconButton(
                    icon: const Icon(Icons.replay_10, color: KumihoTheme.textPrimary),
                    onPressed: () => _seekRelative(-10),
                    tooltip: 'Rewind 10s',
                  ),
                  // Play/Pause
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: KumihoTheme.textPrimary,
                      size: 32,
                    ),
                    onPressed: togglePlayPause,
                    tooltip: _isPlaying ? 'Pause (Space)' : 'Play (Space)',
                  ),
                  // Forward
                  IconButton(
                    icon: const Icon(Icons.forward_10, color: KumihoTheme.textPrimary),
                    onPressed: () => _seekRelative(10),
                    tooltip: 'Forward 10s',
                  ),
                  const SizedBox(width: 16),
                  // Volume
                  IconButton(
                    icon: Icon(
                      _isMuted || _volume == 0 ? Icons.volume_off : Icons.volume_up,
                      color: KumihoTheme.textPrimary,
                    ),
                    onPressed: toggleMute,
                    tooltip: _isMuted ? 'Unmute (M)' : 'Mute (M)',
                  ),
                  SizedBox(
                    width: 100,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      ),
                      child: Slider(
                        value: _isMuted ? 0 : _volume,
                        onChanged: (value) {
                          setState(() {
                            _volume = value;
                            _isMuted = value == 0;
                          });
                          _player?.setVolume(value * 100);
                        },
                        activeColor: KumihoTheme.primary,
                        inactiveColor: KumihoTheme.textDimmed,
                      ),
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
