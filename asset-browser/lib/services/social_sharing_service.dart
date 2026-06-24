// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../providers/settings_provider.dart';
import 'oauth_service.dart';

/// Result of a social media post
class ShareResult {
  final bool success;
  final String? postUrl;
  final String? error;

  const ShareResult({
    required this.success,
    this.postUrl,
    this.error,
  });

  factory ShareResult.success({String? postUrl}) => ShareResult(
    success: true,
    postUrl: postUrl,
  );

  factory ShareResult.failure(String error) => ShareResult(
    success: false,
    error: error,
  );
}

/// Service for posting to social media platforms using their APIs
class SocialSharingService {
  // Twitter/X API v2 endpoints
  static const _twitterApiBase = 'https://api.twitter.com/2';
  static const _twitterUploadBase = 'https://upload.twitter.com/1.1';
  
  // LinkedIn API endpoints
  static const _linkedInApiBase = 'https://api.linkedin.com/v2';

  // Reddit API endpoints
  static const _redditApiBase = 'https://oauth.reddit.com';
  
  /// Post to Twitter/X with image attachment using OAuth 1.0a
  /// Requires OAuth 1.0a access token and token secret for media upload
  static Future<ShareResult> postToTwitter({
    required String accessToken,
    String? accessTokenSecret,
    required String text,
    String? imagePath,
  }) async {
    try {
      await OAuthService().loadCredentials();
      if (!OAuthService().hasTwitterCredentials) {
        return ShareResult.failure(
          'No X/Twitter API credentials configured. Add your own API key and '
          'secret in Settings → Social App Credentials.',
        );
      }

      String? mediaId;

      // Upload image first if provided (requires OAuth 1.0a)
      if (imagePath != null && accessTokenSecret != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          mediaId = await _uploadTwitterMedia(accessToken, accessTokenSecret, file);
        }
      }
      
      // Create tweet using OAuth 1.0a
      final tweetResult = await _postTweet(accessToken, accessTokenSecret!, text, mediaId);
      return tweetResult;
    } catch (e) {
      debugPrint('Twitter post error: $e');
      return ShareResult.failure('Failed to post: $e');
    }
  }
  
  /// Post a tweet using Twitter API v2 with OAuth 1.0a
  /// The v2 API is available on the Free tier, unlike v1.1 statuses/update
  static Future<ShareResult> _postTweet(
    String accessToken,
    String accessTokenSecret,
    String text,
    String? mediaId,
  ) async {
    try {
      final url = '$_twitterApiBase/tweets';
      final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final nonce = _generateNonce();
      
      // OAuth parameters (body is JSON, not included in signature base)
      final oauthParams = <String, String>{
        'oauth_consumer_key': OAuthService().twitterConsumerKey,
        'oauth_nonce': nonce,
        'oauth_signature_method': 'HMAC-SHA1',
        'oauth_timestamp': timestamp,
        'oauth_token': accessToken,
        'oauth_version': '1.0',
      };
      
      final signature = _generateOAuth1Signature(
        'POST',
        url,
        oauthParams, // Only OAuth params for signature, not JSON body
        OAuthService().twitterConsumerSecret,
        accessTokenSecret,
      );
      
      oauthParams['oauth_signature'] = signature;
      
      final authHeader = _buildOAuth1Header(oauthParams);
      
      // Build JSON body for v2 API
      final Map<String, dynamic> jsonBody = {
        'text': text,
      };
      if (mediaId != null) {
        jsonBody['media'] = {
          'media_ids': [mediaId],
        };
      }
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(jsonBody),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final tweetId = data['data']?['id'];
        return ShareResult.success(
          postUrl: tweetId != null 
              ? 'https://twitter.com/i/web/status/$tweetId'
              : null,
        );
      } else {
        final error = jsonDecode(response.body);
        final errorMessage = error['detail'] ?? 
            error['title'] ??
            error['errors']?[0]?['message'] ?? 
            'Failed to post to Twitter';
        return ShareResult.failure(errorMessage);
      }
    } catch (e) {
      debugPrint('Tweet post error: $e');
      return ShareResult.failure('Failed to post: $e');
    }
  }

  /// Check if file is a video based on extension
  static bool _isVideoFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ['mp4', 'mov', 'avi', 'webm', 'mkv'].contains(ext);
  }

  /// Upload media to Twitter using OAuth 1.0a
  /// Uses simple upload for images, chunked upload for videos
  static Future<String?> _uploadTwitterMedia(
    String accessToken,
    String accessTokenSecret,
    File file,
  ) async {
    try {
      final mimeType = _getMimeType(file.path);
      final isVideo = _isVideoFile(file.path);
      
      if (isVideo) {
        // Videos require chunked upload
        return await _uploadTwitterVideoChunked(accessToken, accessTokenSecret, file, mimeType);
      } else {
        // Images use simple upload
        return await _uploadTwitterImage(accessToken, accessTokenSecret, file);
      }
    } catch (e, stackTrace) {
      debugPrint('Twitter media upload error: $e\n$stackTrace');
      return null;
    }
  }

  /// Upload image to Twitter using simple upload
  static Future<String?> _uploadTwitterImage(
    String accessToken,
    String accessTokenSecret,
    File file,
  ) async {
    final bytes = await file.readAsBytes();
    final totalBytes = bytes.length;
    
    // Check file size - Twitter limits images to 5MB for simple upload
    if (totalBytes > 5 * 1024 * 1024) {
      return null;
    }
    
    // Simple upload uses base64 encoded media
    final base64Media = base64Encode(bytes);
    
    final url = '$_twitterUploadBase/media/upload.json';
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = _generateNonce();
    
    // OAuth parameters only (body params not included in signature for multipart)
    final oauthParams = <String, String>{
      'oauth_consumer_key': OAuthService().twitterConsumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_token': accessToken,
      'oauth_version': '1.0',
    };
    
    final signature = _generateOAuth1Signature(
      'POST',
      url,
      oauthParams,
      OAuthService().twitterConsumerSecret,
      accessTokenSecret,
    );
    
    oauthParams['oauth_signature'] = signature;
    
    final authHeader = _buildOAuth1Header(oauthParams);
    
    // Create multipart request
    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.headers['Authorization'] = authHeader;
    request.fields['media_data'] = base64Media;
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200 || response.statusCode == 202) {
      final data = jsonDecode(response.body);
      return data['media_id_string'] as String?;
    }
    return null;
  }

  /// Upload video to Twitter using chunked upload (INIT, APPEND, FINALIZE)
  /// Twitter requires chunked upload for videos
  static Future<String?> _uploadTwitterVideoChunked(
    String accessToken,
    String accessTokenSecret,
    File file,
    String mimeType,
  ) async {
    final bytes = await file.readAsBytes();
    final totalBytes = bytes.length;
    
    // Twitter video limits: 512MB for videos, but Free tier may have lower limits
    // Videos must be MP4 or MOV, max 2:20 duration
    if (totalBytes > 512 * 1024 * 1024) {
      return null;
    }
    
    final url = '$_twitterUploadBase/media/upload.json';
    
    // Step 1: INIT - Initialize the upload
    final initMediaId = await _twitterChunkedInit(
      accessToken, accessTokenSecret, url, totalBytes, mimeType,
    );
    if (initMediaId == null) {
      return null;
    }
    
    // Step 2: APPEND - Upload chunks (5MB chunks)
    const chunkSize = 5 * 1024 * 1024; // 5MB chunks
    int segmentIndex = 0;
    
    for (int offset = 0; offset < totalBytes; offset += chunkSize) {
      final end = (offset + chunkSize > totalBytes) ? totalBytes : offset + chunkSize;
      final chunk = bytes.sublist(offset, end);
      
      final appendSuccess = await _twitterChunkedAppend(
        accessToken, accessTokenSecret, url, initMediaId, segmentIndex, chunk,
      );
      if (!appendSuccess) {
        return null;
      }
      segmentIndex++;
    }
    
    // Step 3: FINALIZE - Complete the upload
    final finalizeSuccess = await _twitterChunkedFinalize(
      accessToken, accessTokenSecret, url, initMediaId,
    );
    if (!finalizeSuccess) {
      return null;
    }
    
    // Step 4: Check processing status (videos need async processing)
    final ready = await _twitterCheckProcessingStatus(
      accessToken, accessTokenSecret, url, initMediaId,
    );
    if (!ready) {
      return null;
    }
    
    return initMediaId;
  }

  /// Twitter chunked upload INIT command
  static Future<String?> _twitterChunkedInit(
    String accessToken,
    String accessTokenSecret,
    String url,
    int totalBytes,
    String mimeType,
  ) async {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = _generateNonce();
    
    // Body parameters for form-urlencoded request
    final bodyParams = <String, String>{
      'command': 'INIT',
      'total_bytes': totalBytes.toString(),
      'media_type': mimeType,
      'media_category': 'tweet_video',
    };
    
    // OAuth params + body params for signature (form-urlencoded includes body in signature)
    final allParams = <String, String>{
      'oauth_consumer_key': OAuthService().twitterConsumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_token': accessToken,
      'oauth_version': '1.0',
      ...bodyParams,
    };
    
    final signature = _generateOAuth1Signature(
      'POST', url, allParams,
      OAuthService().twitterConsumerSecret, accessTokenSecret,
    );
    
    // Only OAuth params go in the header (not body params)
    final oauthParams = <String, String>{
      'oauth_consumer_key': OAuthService().twitterConsumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_token': accessToken,
      'oauth_version': '1.0',
      'oauth_signature': signature,
    };
    
    final authHeader = _buildOAuth1Header(oauthParams);
    
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: bodyParams,
    );
    
    if (response.statusCode == 200 || response.statusCode == 202) {
      final data = jsonDecode(response.body);
      return data['media_id_string'] as String?;
    }
    return null;
  }

  /// Twitter chunked upload APPEND command
  static Future<bool> _twitterChunkedAppend(
    String accessToken,
    String accessTokenSecret,
    String url,
    String mediaId,
    int segmentIndex,
    List<int> chunk,
  ) async {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = _generateNonce();
    
    final oauthParams = <String, String>{
      'oauth_consumer_key': OAuthService().twitterConsumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_token': accessToken,
      'oauth_version': '1.0',
    };
    
    final signature = _generateOAuth1Signature(
      'POST', url, oauthParams,
      OAuthService().twitterConsumerSecret, accessTokenSecret,
    );
    oauthParams['oauth_signature'] = signature;
    
    final authHeader = _buildOAuth1Header(oauthParams);
    
    // Use multipart for APPEND with binary data
    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.headers['Authorization'] = authHeader;
    request.fields['command'] = 'APPEND';
    request.fields['media_id'] = mediaId;
    request.fields['segment_index'] = segmentIndex.toString();
    request.files.add(http.MultipartFile.fromBytes('media', chunk, filename: 'chunk'));
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    // APPEND returns 204 No Content on success
    return response.statusCode == 204 || response.statusCode == 200;
  }

  /// Twitter chunked upload FINALIZE command
  static Future<bool> _twitterChunkedFinalize(
    String accessToken,
    String accessTokenSecret,
    String url,
    String mediaId,
  ) async {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = _generateNonce();
    
    // Body parameters for form-urlencoded request
    final bodyParams = <String, String>{
      'command': 'FINALIZE',
      'media_id': mediaId,
    };
    
    // OAuth params + body params for signature (form-urlencoded includes body in signature)
    final allParams = <String, String>{
      'oauth_consumer_key': OAuthService().twitterConsumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_token': accessToken,
      'oauth_version': '1.0',
      ...bodyParams,
    };
    
    final signature = _generateOAuth1Signature(
      'POST', url, allParams,
      OAuthService().twitterConsumerSecret, accessTokenSecret,
    );
    
    // Only OAuth params go in the header
    final oauthParams = <String, String>{
      'oauth_consumer_key': OAuthService().twitterConsumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_token': accessToken,
      'oauth_version': '1.0',
      'oauth_signature': signature,
    };
    
    final authHeader = _buildOAuth1Header(oauthParams);
    
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: bodyParams,
    );
    
    return response.statusCode == 200 || response.statusCode == 201;
  }

  /// Check video processing status (poll until complete or failed)
  static Future<bool> _twitterCheckProcessingStatus(
    String accessToken,
    String accessTokenSecret,
    String baseUrl,
    String mediaId,
  ) async {
    // Poll for up to 60 seconds (videos take time to process)
    const maxAttempts = 30;
    const pollInterval = Duration(seconds: 2);
    
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final nonce = _generateNonce();
      
      // For GET request, include query params in signature
      final queryParams = {
        'command': 'STATUS',
        'media_id': mediaId,
      };
      
      final oauthParams = <String, String>{
        'oauth_consumer_key': OAuthService().twitterConsumerKey,
        'oauth_nonce': nonce,
        'oauth_signature_method': 'HMAC-SHA1',
        'oauth_timestamp': timestamp,
        'oauth_token': accessToken,
        'oauth_version': '1.0',
        ...queryParams,
      };
      
      final signature = _generateOAuth1Signature(
        'GET', baseUrl, oauthParams,
        OAuthService().twitterConsumerSecret, accessTokenSecret,
      );
      
      // Remove query params from oauth header
      final headerParams = <String, String>{
        'oauth_consumer_key': OAuthService().twitterConsumerKey,
        'oauth_nonce': nonce,
        'oauth_signature_method': 'HMAC-SHA1',
        'oauth_timestamp': timestamp,
        'oauth_token': accessToken,
        'oauth_version': '1.0',
        'oauth_signature': signature,
      };
      
      final authHeader = _buildOAuth1Header(headerParams);
      
      final url = '$baseUrl?command=STATUS&media_id=$mediaId';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': authHeader},
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final processingInfo = data['processing_info'];
        
        if (processingInfo == null) {
          // No processing info means it's ready
          return true;
        }
        
        final state = processingInfo['state'] as String?;
        if (state == 'succeeded') {
          return true;
        } else if (state == 'failed') {
          final error = processingInfo['error'];
          debugPrint('Twitter video processing failed: $error');
          return false;
        }
        
        // Still processing, wait and retry
        final checkAfterSecs = processingInfo['check_after_secs'] as int? ?? 2;
        await Future.delayed(Duration(seconds: checkAfterSecs));
      } else {
        // Error checking status
        debugPrint('Twitter STATUS check failed: ${response.statusCode}');
        return false;
      }
    }
    
    return false;
  }
  
  /// Generate OAuth 1.0a signature
  static String _generateOAuth1Signature(
    String method,
    String url,
    Map<String, String> params,
    String consumerSecret,
    String tokenSecret,
  ) {
    // Sort parameters
    final sortedParams = Map.fromEntries(
      params.entries.toList()..sort((a, b) => a.key.compareTo(b.key))
    );
    
    // Create parameter string
    final paramString = sortedParams.entries
        .map((e) => '${_percentEncode(e.key)}=${_percentEncode(e.value)}')
        .join('&');
    
    // Create signature base string
    final signatureBase = [
      method.toUpperCase(),
      _percentEncode(url),
      _percentEncode(paramString),
    ].join('&');
    
    // Create signing key
    final signingKey = '${_percentEncode(consumerSecret)}&${_percentEncode(tokenSecret)}';
    
    // Generate HMAC-SHA1
    final hmac = Hmac(sha1, utf8.encode(signingKey));
    final digest = hmac.convert(utf8.encode(signatureBase));
    
    return base64Encode(digest.bytes);
  }
  
  /// Build OAuth 1.0a Authorization header
  static String _buildOAuth1Header(Map<String, String> params) {
    final pairs = params.entries
        .map((e) => '${_percentEncode(e.key)}="${_percentEncode(e.value)}"')
        .join(', ');
    return 'OAuth $pairs';
  }
  
  /// Percent encode for OAuth 1.0a
  static String _percentEncode(String value) {
    return Uri.encodeComponent(value)
        .replaceAll('!', '%21')
        .replaceAll("'", '%27')
        .replaceAll('(', '%28')
        .replaceAll(')', '%29')
        .replaceAll('*', '%2A');
  }
  
  /// Generate random nonce
  static String _generateNonce() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  }

  /// Post to LinkedIn with image attachment
  /// Requires OAuth 2.0 access token with w_member_social scope
  static Future<ShareResult> postToLinkedIn({
    required String accessToken,
    required String authorUrn, // urn:li:person:XXXXX
    required String text,
    String? imagePath,
  }) async {
    try {
      String? assetUrn;
      
      // Upload image first if provided
      if (imagePath != null) {
        final file = File(imagePath);
        if (await file.exists()) {
          assetUrn = await _uploadLinkedInMedia(accessToken, authorUrn, file);
        }
      }
      
      // Create post
      final Map<String, dynamic> shareContent = {
        'author': authorUrn,
        'lifecycleState': 'PUBLISHED',
        'specificContent': {
          'com.linkedin.ugc.ShareContent': {
            'shareCommentary': {
              'text': text,
            },
            'shareMediaCategory': assetUrn != null ? 'IMAGE' : 'NONE',
            if (assetUrn != null) 'media': [
              {
                'status': 'READY',
                'media': assetUrn,
              }
            ],
          },
        },
        'visibility': {
          'com.linkedin.ugc.MemberNetworkVisibility': 'PUBLIC',
        },
      };

      final response = await http.post(
        Uri.parse('$_linkedInApiBase/ugcPosts'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'X-Restli-Protocol-Version': '2.0.0',
        },
        body: jsonEncode(shareContent),
      );

      if (response.statusCode == 201) {
        final postId = response.headers['x-restli-id'];
        return ShareResult.success(
          postUrl: postId != null 
            ? 'https://www.linkedin.com/feed/update/$postId'
            : null,
        );
      } else {
        final error = jsonDecode(response.body);
        return ShareResult.failure(
          error['message'] ?? 'Failed to post to LinkedIn',
        );
      }
    } catch (e) {
      debugPrint('LinkedIn post error: $e');
      return ShareResult.failure('Failed to post: $e');
    }
  }

  /// Post to Reddit (profile by default) using OAuth 2.0 access token
  ///
  /// Reddit requires a target subreddit (`sr`). To keep UX simple and consistent
  /// with "Post to X", we post to the user's own profile by default via `u_<username>`.
  static Future<ShareResult> postToReddit({
    required String accessToken,
    required String username, // Reddit username (e.g. "someuser")
    required String title,
    String? url,
    String? text,
  }) async {
    // Temporarily disabled until Reddit API keys are provisioned
    return ShareResult.failure('Reddit integration coming soon! API keys are pending.');
    
    // ignore: dead_code
    try {
      final sr = username.isNotEmpty ? 'u_$username' : '';
      if (sr.isEmpty) {
        return ShareResult.failure('Reddit username missing. Please reconnect in Settings.');
      }

      final trimmedTitle = title.trim();
      if (trimmedTitle.isEmpty) {
        return ShareResult.failure('Title is required for Reddit posts.');
      }

      final kind = (url != null && url.trim().isNotEmpty) ? 'link' : 'self';

      final body = <String, String>{
        'sr': sr,
        'kind': kind,
        'title': trimmedTitle.length > 300 ? trimmedTitle.substring(0, 300) : trimmedTitle,
        'api_type': 'json',
      };

      if (kind == 'link') {
        body['url'] = url!.trim();
      } else {
        final selfText = (text ?? '').trim();
        if (selfText.isNotEmpty) {
          body['text'] = selfText;
        }
      }

      final response = await http.post(
        Uri.parse('$_redditApiBase/api/submit'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
          'User-Agent': 'KumihoAssetBrowser/1.0 (by kumihoclouds)',
        },
        body: body,
      );

      if (response.statusCode != 200) {
        return ShareResult.failure('Reddit post failed: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final json = decoded['json'] as Map<String, dynamic>?;
      final errors = (json?['errors'] as List?) ?? const [];

      if (errors.isNotEmpty) {
        final first = errors.first;
        if (first is List && first.isNotEmpty) {
          return ShareResult.failure(first.last?.toString() ?? 'Failed to post to Reddit');
        }
        return ShareResult.failure('Failed to post to Reddit');
      }

      final data = json?['data'] as Map<String, dynamic>?;
      final postUrl = data?['url'] as String?;
      return ShareResult.success(postUrl: postUrl);
    } catch (e) {
      debugPrint('Reddit post error: $e');
      return ShareResult.failure('Failed to post: $e');
    }
  }

  /// Upload media to LinkedIn and return asset URN
  static Future<String?> _uploadLinkedInMedia(
    String accessToken, 
    String authorUrn, 
    File file,
  ) async {
    try {
      // Register upload
      final registerResponse = await http.post(
        Uri.parse('$_linkedInApiBase/assets?action=registerUpload'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
          'X-Restli-Protocol-Version': '2.0.0',
        },
        body: jsonEncode({
          'registerUploadRequest': {
            'recipes': ['urn:li:digitalmediaRecipe:feedshare-image'],
            'owner': authorUrn,
            'serviceRelationships': [
              {
                'relationshipType': 'OWNER',
                'identifier': 'urn:li:userGeneratedContent',
              }
            ],
          },
        }),
      );

      if (registerResponse.statusCode != 200) {
        debugPrint('LinkedIn register upload failed: ${registerResponse.body}');
        return null;
      }

      final registerData = jsonDecode(registerResponse.body);
      final uploadUrl = registerData['value']['uploadMechanism']
          ['com.linkedin.digitalmedia.uploading.MediaUploadHttpRequest']['uploadUrl'];
      final assetUrn = registerData['value']['asset'];

      // Upload the file
      final bytes = await file.readAsBytes();
      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': _getMimeType(file.path),
        },
        body: bytes,
      );

      if (uploadResponse.statusCode == 201 || uploadResponse.statusCode == 200) {
        return assetUrn;
      } else {
        debugPrint('LinkedIn upload failed: ${uploadResponse.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('LinkedIn media upload error: $e');
      return null;
    }
  }

  /// Get the MIME type for a file
  static String _getMimeType(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      default:
        return 'application/octet-stream';
    }
  }

  /// Parse stored account JSON to get access token
  static SocialAccount? parseAccountJson(String? json) {
    if (json == null) return null;
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return SocialAccount.fromJson(data);
    } catch (e) {
      debugPrint('Failed to parse social account: $e');
      return null;
    }
  }

  /// Check if a token is expired and needs refresh
  static bool isTokenExpired(SocialAccount? account) {
    if (account == null) return true;
    return account.isExpired;
  }

  /// Open browser-based sharing as fallback
  static Future<bool> openBrowserShare({
    required String platform,
    required String text,
    String? url,
  }) async {
    final encodedText = Uri.encodeComponent(text);
    String shareUrl;

    switch (platform.toLowerCase()) {
      case 'twitter':
      case 'x':
        shareUrl = 'https://twitter.com/intent/tweet?text=$encodedText';
        if (url != null) {
          shareUrl += '&url=${Uri.encodeComponent(url)}';
        }
        break;
      case 'facebook':
        if (url != null) {
          shareUrl = 'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(url)}&quote=$encodedText';
        } else {
          return false; // Facebook requires URL
        }
        break;
      case 'linkedin':
        if (url != null) {
          shareUrl = 'https://www.linkedin.com/sharing/share-offsite/?url=${Uri.encodeComponent(url)}';
        } else {
          return false; // LinkedIn requires URL
        }
        break;
      case 'reddit':
        if (url != null) {
          shareUrl = 'https://www.reddit.com/submit?url=${Uri.encodeComponent(url)}&title=$encodedText';
        } else {
          shareUrl = 'https://www.reddit.com/submit?title=$encodedText&text=${Uri.encodeComponent(text)}';
        }
        break;
      default:
        return false;
    }

    final uri = Uri.parse(shareUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }
}
