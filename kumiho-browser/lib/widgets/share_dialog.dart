// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../providers/settings_provider.dart';
import '../services/social_sharing_service.dart';
import '../theme/kumiho_theme.dart';
import 'video_thumbnail.dart';

/// Social media platform for sharing
enum SocialPlatform {
  native,   // Native OS share sheet with image attachment
  twitter,
  facebook,
  linkedin,
  reddit,
}

/// Show the share dialog for a media item
Future<void> showShareDialog(BuildContext context, MediaItem item) async {
  return showDialog(
    context: context,
    builder: (context) => _ShareDialog(item: item),
  );
}

class _ShareDialog extends ConsumerStatefulWidget {
  final MediaItem item;

  const _ShareDialog({required this.item});

  @override
  ConsumerState<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<_ShareDialog> {
  late TextEditingController _messageController;
  bool _isSharing = false;
  String? _shareError;
  SocialPlatform? _lastSharedTo;
  String? _postUrl;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _messageController = TextEditingController(text: settings.defaultShareMessage);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  /// Get the best local media path for sharing (image or video)
  /// Prefers artifact location, falls back to thumbnailPath
  String? get _localMediaPath {
    final item = widget.item;
    
    // For both images and videos, prefer the artifact location (full resolution)
    if (item.location != null) {
      final locPath = item.location!;
      if (!locPath.startsWith('http://') && !locPath.startsWith('https://')) {
        try {
          final file = File(locPath);
          if (file.existsSync()) return locPath;
        } catch (_) {}
      }
    }
    
    // For videos, thumbnailPath might point to the video file
    if (item.isVideo && item.thumbnailPath != null) {
      final path = item.thumbnailPath!;
      if (!path.startsWith('http://') && !path.startsWith('https://')) {
        try {
          final file = File(path);
          if (file.existsSync()) return path;
        } catch (_) {}
      }
    }
    
    // For images, fall back to thumbnailPath
    if (item.isImage) {
      final path = item.thumbnailPath;
      if (path != null && !path.startsWith('http://') && !path.startsWith('https://')) {
        try {
          final file = File(path);
          if (file.existsSync()) return path;
        } catch (_) {}
      }
    }
    
    return null;
  }

  /// Check if we have a local media file that can be shared
  bool get _hasLocalMedia => _localMediaPath != null;
  
  /// Check if we have an HTTP image that can be downloaded
  bool get _hasHttpImage {
    final path = widget.item.thumbnailPath;
    if (path == null) return false;
    return path.startsWith('http://') || path.startsWith('https://');
  }
  
  /// Check if we have any shareable media (local or HTTP)
  bool get _hasShareableMedia => _hasLocalMedia || _hasHttpImage;
  
  /// Get local media path for sharing (image or video)
  Future<String?> _getShareableMediaPath() async {
    // First try local media (artifact location or thumbnailPath)
    final localPath = _localMediaPath;
    if (localPath != null) return localPath;
    
    // For videos, we don't download from HTTP (too large)
    if (widget.item.isVideo) return null;
    
    // Try to download HTTP image
    final path = widget.item.thumbnailPath;
    if (path == null) return null;
    
    if (!path.startsWith('http://') && !path.startsWith('https://')) {
      return null;
    }
    
    // Download HTTP image to temp file
    try {
      final response = await http.get(Uri.parse(path));
      if (response.statusCode != 200) return null;
      
      // Determine file extension from URL or content type
      String extension = 'jpg';
      final contentType = response.headers['content-type'];
      if (contentType != null) {
        if (contentType.contains('png')) extension = 'png';
        else if (contentType.contains('gif')) extension = 'gif';
        else if (contentType.contains('webp')) extension = 'webp';
      } else if (path.contains('.')) {
        final urlExt = path.split('.').last.split('?').first.toLowerCase();
        if (['png', 'gif', 'webp', 'jpg', 'jpeg'].contains(urlExt)) {
          extension = urlExt;
        }
      }
      
      // Save to temp directory
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/share_image_${DateTime.now().millisecondsSinceEpoch}.$extension');
      await tempFile.writeAsBytes(response.bodyBytes);
      
      return tempFile.path;
    } catch (_) {
      return null;
    }
  }

  /// Get Twitter account from settings
  SocialAccount? get _twitterAccount {
    final json = ref.read(settingsProvider).twitterAccountJson;
    return SocialSharingService.parseAccountJson(json);
  }

  /// Get LinkedIn account from settings
  SocialAccount? get _linkedInAccount {
    final json = ref.read(settingsProvider).linkedInAccountJson;
    return SocialSharingService.parseAccountJson(json);
  }

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    final settings = ref.watch(settingsProvider);

    return Dialog(
      backgroundColor: colors.backgroundCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.share, color: KumihoTheme.primary, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Share Asset',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: colors.textMuted, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Item preview
            _ItemPreview(item: widget.item),
            const SizedBox(height: 16),
            
            // Message input
            Text(
              'Message',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              minLines: 4,
              maxLines: 6,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Add a message...',
                hintStyle: TextStyle(color: colors.textDimmed),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: KumihoTheme.primary),
                ),
                filled: true,
                fillColor: colors.backgroundSecondary,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 16),
            
            // Error message
            if (_shareError != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: KumihoTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KumihoTheme.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: KumihoTheme.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _shareError!,
                        style: TextStyle(color: KumihoTheme.error, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            
            // Success message
            if (_lastSharedTo != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: KumihoTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KumihoTheme.success.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: KumihoTheme.success, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _getSuccessMessage(_lastSharedTo!),
                          style: TextStyle(color: KumihoTheme.success, fontSize: 12),
                        ),
                      ],
                    ),
                    if (_postUrl != null) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _openUrl(_postUrl!),
                        child: Text(
                          'View post →',
                          style: TextStyle(
                            color: KumihoTheme.success,
                            fontSize: 11,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            
            // Connected accounts section - always show for X with Reddit/LinkedIn coming soon
            Text(
              'Post directly',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                if (settings.hasTwitterConnected) ...[
                  SizedBox(
                    width: double.infinity,
                    child: _DirectPostButton(
                      platform: 'X',
                      iconWidget: const _XLogo(size: 32),
                      color: colors.textPrimary,
                      account: _twitterAccount,
                      isLoading: _isSharing,
                      onTap: _postToTwitterDirect,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: _ComingSoonButton(
                    platform: 'Reddit',
                    iconWidget: const _RedditLogo(size: 28),
                    color: const Color(0xFFFF4500),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: _ComingSoonButton(
                    platform: 'LinkedIn',
                    iconWidget: const _LinkedInLogo(size: 36),
                    color: const Color(0xFF0A66C2),
                  ),
                ),
              ],
            ),
            
            // Native share with media attachment (not supported on Linux)
            if (_hasLocalMedia && !Platform.isLinux) ...[
              const SizedBox(height: 16),
              Divider(color: colors.border),
              const SizedBox(height: 12),
              Text(
                'Or use native share',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _isSharing ? null : _shareNative,
                  icon: _isSharing 
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.textMuted,
                          ),
                        )
                      : Icon(Icons.ios_share_rounded, size: 16, color: colors.textSecondary),
                  label: Text(
                    'Share to Any App',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    backgroundColor: colors.backgroundSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: colors.border),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            
            // Connect accounts hint
            if (!settings.hasTwitterConnected)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: KumihoTheme.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: KumihoTheme.info.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: KumihoTheme.info, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Connect your X account in Settings to post directly. Reddit is coming soon.',
                        style: TextStyle(color: KumihoTheme.info, fontSize: 11),
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

  String _getSuccessMessage(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.native:
        return 'Share dialog opened!';
      case SocialPlatform.twitter:
        return 'Posted to X!';
      case SocialPlatform.linkedin:
        return 'Posted to LinkedIn!';
      case SocialPlatform.reddit:
        return 'Posted to Reddit!';
      default:
        return 'Shared successfully!';
    }
  }

  String _getShareText() {
    final message = _messageController.text.trim();
    
    if (message.isNotEmpty) {
      return message;
    }
    return 'Created with Kumiho';
  }

  String? _getShareUrl() {
    if (widget.item.hasHttpThumbnail) {
      return widget.item.thumbnailPath;
    }
    return null;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Post directly to Twitter using API
  Future<void> _postToTwitterDirect() async {
    final account = _twitterAccount;
    if (account == null) {
      setState(() => _shareError = 'Twitter account not connected');
      return;
    }

    if (SocialSharingService.isTokenExpired(account)) {
      setState(() => _shareError = 'Twitter token expired. Please reconnect in Settings.');
      return;
    }

    setState(() {
      _isSharing = true;
      _shareError = null;
      _lastSharedTo = null;
      _postUrl = null;
    });

    try {
      // Get the best available media path (artifact location preferred)
      final mediaPath = _localMediaPath;
      
      final result = await SocialSharingService.postToTwitter(
        accessToken: account.accessToken,
        accessTokenSecret: account.accessTokenSecret,
        text: _getShareText(),
        imagePath: mediaPath,
      );

      if (result.success) {
        setState(() {
          _lastSharedTo = SocialPlatform.twitter;
          _postUrl = result.postUrl;
        });
      } else {
        setState(() => _shareError = result.error ?? 'Failed to post to X');
      }
    } catch (e) {
      setState(() => _shareError = 'Failed to post: $e');
    } finally {
      setState(() => _isSharing = false);
    }
  }

  /// Post directly to LinkedIn using API
  Future<void> _postToLinkedInDirect() async {
    final account = _linkedInAccount;
    if (account == null) {
      setState(() => _shareError = 'LinkedIn account not connected');
      return;
    }

    if (SocialSharingService.isTokenExpired(account)) {
      setState(() => _shareError = 'LinkedIn token expired. Please reconnect in Settings.');
      return;
    }

    setState(() {
      _isSharing = true;
      _shareError = null;
      _lastSharedTo = null;
      _postUrl = null;
    });

    try {
      // The username field stores the LinkedIn URN (urn:li:person:XXXXX)
      final authorUrn = account.username;
      
      // Get the best available media path (artifact location preferred)
      final mediaPath = _localMediaPath;
      
      final result = await SocialSharingService.postToLinkedIn(
        accessToken: account.accessToken,
        authorUrn: authorUrn,
        text: _getShareText(),
        imagePath: mediaPath,
      );

      if (result.success) {
        setState(() {
          _lastSharedTo = SocialPlatform.linkedin;
          _postUrl = result.postUrl;
        });
      } else {
        setState(() => _shareError = result.error ?? 'Failed to post to LinkedIn');
      }
    } catch (e) {
      setState(() => _shareError = 'Failed to post: $e');
    } finally {
      setState(() => _isSharing = false);
    }
  }

  /// Share using native OS share sheet with image attachment
  Future<void> _shareNative() async {
    setState(() {
      _isSharing = true;
      _shareError = null;
      _lastSharedTo = null;
      _postUrl = null;
    });

    try {
      // Use artifact location for better quality
      final path = _localMediaPath ?? widget.item.thumbnailPath;
      if (path == null) {
        setState(() => _shareError = 'No media path available');
        return;
      }

      final file = XFile(path);
      final text = _getShareText();
      
      final result = await Share.shareXFiles(
        [file],
        text: text,
        subject: widget.item.name,
      );

      if (result.status == ShareResultStatus.success) {
        setState(() => _lastSharedTo = SocialPlatform.native);
      } else if (result.status == ShareResultStatus.dismissed) {
        // User dismissed, no error
      }
    } catch (e) {
      setState(() => _shareError = 'Failed to share: $e');
    } finally {
      setState(() => _isSharing = false);
    }
  }

}

/// X (Twitter) logo widget using asset image
class _XLogo extends StatelessWidget {
  final double size;

  const _XLogo({this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/X_icon.png',
      width: size,
      height: size,
    );
  }
}

/// LinkedIn logo widget using asset image
class _LinkedInLogo extends StatelessWidget {
  final double size;

  const _LinkedInLogo({this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/linkedin_icon.png',
      width: size,
      height: size,
    );
  }
}

/// Reddit icon widget (uses built-in icon to avoid bundling third-party logos)
class _RedditLogo extends StatelessWidget {
  final double size;

  const _RedditLogo({this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/reddit_icon.png',
      width: size,
      height: size,
    );
  }
}

/// Button for direct posting to connected accounts
class _DirectPostButton extends StatelessWidget {
  final String platform;
  final Widget iconWidget;
  final Color color;
  final SocialAccount? account;
  final bool isLoading;
  final VoidCallback onTap;

  const _DirectPostButton({
    required this.platform,
    required this.iconWidget,
    required this.color,
    required this.account,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    final isConnected = account != null;
    final isExpired = SocialSharingService.isTokenExpired(account);

    final iconContainerSize = 32.0;
    
    return Tooltip(
      message: !isConnected
          ? 'Not connected - connect in Settings'
          : (isExpired ? 'Token expired - reconnect in Settings' : 'Post to $platform'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading || isExpired ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              gradient: isExpired ? null : LinearGradient(
                colors: [
                  color.withValues(alpha: 0.15),
                  color.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              color: isExpired ? colors.backgroundSecondary : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isExpired ? colors.border : color.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: iconContainerSize,
                  height: iconContainerSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: (!isConnected || isExpired) ? 0.5 : 1.0,
                        child: iconWidget,
                      ),
                      if (!isConnected)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Icon(
                            Icons.link_off_rounded,
                            color: colors.textMuted,
                            size: 14,
                          ),
                        )
                      else if (isExpired)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Icon(
                            Icons.close_rounded,
                            color: colors.textMuted,
                            size: 14,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Post to $platform',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isExpired ? colors.textMuted : colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (account != null)
                        Text(
                          isExpired ? 'Token expired' : '@${account!.displayName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isExpired ? KumihoTheme.error : colors.textDimmed,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isExpired) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.warning_amber_rounded,
                    color: KumihoTheme.warning,
                    size: 14,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Button for coming soon platforms
class _ComingSoonButton extends StatelessWidget {
  final String platform;
  final Widget iconWidget;
  final Color color;

  const _ComingSoonButton({
    required this.platform,
    required this.iconWidget,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return Tooltip(
      message: '$platform integration coming soon!',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(opacity: 0.5, child: iconWidget),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    platform,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Coming soon',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textDimmed,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
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

class _ItemPreview extends StatelessWidget {
  final MediaItem item;

  const _ItemPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: item.thumbColor,
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildThumbnail(),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.kind} • ${item.revision}',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                  ),
                ),
                if (item.thumbnailPath != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        item.hasHttpThumbnail ? Icons.cloud_outlined : Icons.folder_outlined,
                        size: 12,
                        color: colors.textDimmed,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.hasHttpThumbnail ? 'Web image' : 'Local file',
                          style: TextStyle(
                            color: colors.textDimmed,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Check if the thumbnail path is an image (not a video file)
  bool get _hasImageThumbnail {
    if (item.thumbnailPath == null) return false;
    if (item.hasHttpThumbnail) return true;
    final path = item.thumbnailPath!.toLowerCase();
    return path.endsWith('.png') || 
           path.endsWith('.jpg') || 
           path.endsWith('.jpeg') || 
           path.endsWith('.webp') ||
           path.endsWith('.gif');
  }

  /// Get the video path for thumbnail extraction
  String? get _videoPath {
    // For videos, prefer location (artifact), then thumbnailPath
    if (item.isVideo) {
      if (item.location != null) {
        final file = File(item.location!);
        if (file.existsSync()) return item.location;
      }
      if (item.thumbnailPath != null) {
        final file = File(item.thumbnailPath!);
        if (file.existsSync()) return item.thumbnailPath;
      }
    }
    return null;
  }

  Widget _buildThumbnail() {
    // For videos without an image thumbnail, use VideoThumbnail widget
    if (item.isVideo && !_hasImageThumbnail) {
      final videoPath = _videoPath;
          final src = item.location ?? videoPath;
          if (src != null) {
        return VideoThumbnail(
              videoPath: src,
          fit: BoxFit.cover,
          placeholder: _buildLoadingIndicator(),
          errorWidget: _buildPlaceholder(),
        );
      }
    }
    
    // Image thumbnail from local file
    if (item.hasLocalThumbnail && _hasImageThumbnail) {
      return Image.file(
        File(item.thumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }
    
    // Image thumbnail from HTTP
    if (item.hasHttpThumbnail) {
      return Image.network(
        item.thumbnailPath!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }
    
    return _buildPlaceholder();
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white54,
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        item.isVideo ? Icons.videocam : Icons.image,
        color: Colors.white54,
        size: 24,
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final SocialPlatform platform;
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback onTap;

  const _SocialButton({
    required this.platform,
    required this.icon,
    required this.label,
    required this.color,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = KumihoTheme.of(context);
    
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
