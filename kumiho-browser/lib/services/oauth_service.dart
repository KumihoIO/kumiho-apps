// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/settings_provider.dart';

/// OAuth configuration for social platforms (OAuth 2.0)
class OAuthConfig {
  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final List<String> scopes;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  
  const OAuthConfig({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    required this.scopes,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
  });
}

/// OAuth 1.0a configuration for Twitter
class OAuth1Config {
  final String consumerKey;
  final String consumerSecret;
  final String requestTokenUrl;
  final String authorizeUrl;
  final String accessTokenUrl;
  final String callbackUrl;
  
  const OAuth1Config({
    required this.consumerKey,
    required this.consumerSecret,
    required this.requestTokenUrl,
    required this.authorizeUrl,
    required this.accessTokenUrl,
    required this.callbackUrl,
  });
}

/// Service for handling OAuth authentication flows
/// 
/// Uses a local HTTP server to receive OAuth callbacks from the browser.
class OAuthService {
  // Singleton instance
  static final OAuthService _instance = OAuthService._internal();
  factory OAuthService() => _instance;
  OAuthService._internal();

  // Local callback server port
  static const int _callbackPort = 8642;
  HttpServer? _server;

  // ---------------------------------------------------------------------------
  // Bring-your-own OAuth app credentials.
  //
  // No API keys are bundled with the app. Each user registers their own
  // developer app with the relevant platform and enters the resulting
  // client/consumer credentials in Settings -> Social App Credentials. They are
  // stored locally (SharedPreferences) and loaded on demand.
  // ---------------------------------------------------------------------------

  // SharedPreferences keys for user-supplied app credentials.
  static const _kTwitterConsumerKey = 'oauth_twitter_consumer_key';
  static const _kTwitterConsumerSecret = 'oauth_twitter_consumer_secret';
  static const _kLinkedInClientId = 'oauth_linkedin_client_id';
  static const _kLinkedInClientSecret = 'oauth_linkedin_client_secret';
  static const _kRedditClientId = 'oauth_reddit_client_id';
  static const _kRedditClientSecret = 'oauth_reddit_client_secret';

  // Fixed (non-secret) platform endpoints.
  static const _callbackUrl = 'http://localhost:8642/callback';
  static const _twitterRequestTokenUrl = 'https://api.twitter.com/oauth/request_token';
  static const _twitterAuthorizeUrl = 'https://api.twitter.com/oauth/authorize';
  static const _twitterAccessTokenUrl = 'https://api.twitter.com/oauth/access_token';

  // In-memory cache of user-supplied credentials (empty until loaded/entered).
  String _twitterConsumerKey = '';
  String _twitterConsumerSecret = '';
  String _linkedInClientId = '';
  String _linkedInClientSecret = '';
  String _redditClientId = '';
  String _redditClientSecret = '';
  bool _credentialsLoaded = false;

  /// Load user-supplied OAuth app credentials from local storage.
  /// Idempotent; pass [force] to re-read after the user updates them.
  Future<void> loadCredentials({bool force = false}) async {
    if (_credentialsLoaded && !force) return;
    final prefs = await SharedPreferences.getInstance();
    _twitterConsumerKey = prefs.getString(_kTwitterConsumerKey) ?? '';
    _twitterConsumerSecret = prefs.getString(_kTwitterConsumerSecret) ?? '';
    _linkedInClientId = prefs.getString(_kLinkedInClientId) ?? '';
    _linkedInClientSecret = prefs.getString(_kLinkedInClientSecret) ?? '';
    _redditClientId = prefs.getString(_kRedditClientId) ?? '';
    _redditClientSecret = prefs.getString(_kRedditClientSecret) ?? '';
    _credentialsLoaded = true;
  }

  /// Persist the user's X/Twitter API key and secret.
  Future<void> saveTwitterCredentials({
    required String consumerKey,
    required String consumerSecret,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _twitterConsumerKey = consumerKey.trim();
    _twitterConsumerSecret = consumerSecret.trim();
    await prefs.setString(_kTwitterConsumerKey, _twitterConsumerKey);
    await prefs.setString(_kTwitterConsumerSecret, _twitterConsumerSecret);
    _credentialsLoaded = true;
  }

  /// Persist the user's LinkedIn client id and secret.
  Future<void> saveLinkedInCredentials({
    required String clientId,
    required String clientSecret,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _linkedInClientId = clientId.trim();
    _linkedInClientSecret = clientSecret.trim();
    await prefs.setString(_kLinkedInClientId, _linkedInClientId);
    await prefs.setString(_kLinkedInClientSecret, _linkedInClientSecret);
    _credentialsLoaded = true;
  }

  /// Persist the user's Reddit client id and secret.
  Future<void> saveRedditCredentials({
    required String clientId,
    required String clientSecret,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _redditClientId = clientId.trim();
    _redditClientSecret = clientSecret.trim();
    await prefs.setString(_kRedditClientId, _redditClientId);
    await prefs.setString(_kRedditClientSecret, _redditClientSecret);
    _credentialsLoaded = true;
  }

  /// Whether the user has supplied X/Twitter app credentials.
  bool get hasTwitterCredentials =>
      _twitterConsumerKey.isNotEmpty && _twitterConsumerSecret.isNotEmpty;

  /// Twitter OAuth 1.0a configuration, built from the user's credentials.
  OAuth1Config get _twitter1Config => OAuth1Config(
        consumerKey: _twitterConsumerKey,
        consumerSecret: _twitterConsumerSecret,
        requestTokenUrl: _twitterRequestTokenUrl,
        authorizeUrl: _twitterAuthorizeUrl,
        accessTokenUrl: _twitterAccessTokenUrl,
        callbackUrl: _callbackUrl,
      );

  /// LinkedIn OAuth 2.0 configuration, built from the user's credentials.
  OAuthConfig get _linkedInConfig => OAuthConfig(
        clientId: _linkedInClientId,
        clientSecret: _linkedInClientSecret,
        redirectUri: _callbackUrl,
        scopes: const ['openid', 'profile', 'w_member_social'],
        authorizationEndpoint: 'https://www.linkedin.com/oauth/v2/authorization',
        tokenEndpoint: 'https://www.linkedin.com/oauth/v2/accessToken',
      );

  /// Reddit OAuth 2.0 configuration, built from the user's credentials.
  OAuthConfig get _redditConfig => OAuthConfig(
        clientId: _redditClientId,
        clientSecret: _redditClientSecret,
        redirectUri: _callbackUrl,
        scopes: const ['identity', 'submit'],
        authorizationEndpoint: 'https://www.reddit.com/api/v1/authorize.compact',
        tokenEndpoint: 'https://www.reddit.com/api/v1/access_token',
      );

  /// User-supplied X/Twitter consumer (API) key, used for OAuth 1.0a signing.
  String get twitterConsumerKey => _twitterConsumerKey;

  /// User-supplied X/Twitter consumer (API) secret, used for OAuth 1.0a signing.
  String get twitterConsumerSecret => _twitterConsumerSecret;

  /// Current credential values, for prefilling the Settings UI.
  String get linkedInClientId => _linkedInClientId;
  String get linkedInClientSecret => _linkedInClientSecret;
  String get redditClientId => _redditClientId;
  String get redditClientSecret => _redditClientSecret;

  /// Authenticate with Twitter using OAuth 1.0a (3-legged flow)
  /// This is required for media upload as it doesn't support OAuth 2.0
  Future<SocialAccount?> authenticateTwitter() async {
    await loadCredentials();
    if (!hasTwitterCredentials) {
      throw Exception(
        'No X/Twitter API credentials configured. Register your own app in the '
        'X Developer Portal and add the API key and secret in '
        'Settings → Social App Credentials.',
      );
    }
    try {
      // Step 1: Get request token
      final requestTokenResult = await _getTwitterRequestToken();
      if (requestTokenResult == null) {
        debugPrint('Failed to get request token');
        return null;
      }
      
      final oauthToken = requestTokenResult['oauth_token']!;
      final oauthTokenSecret = requestTokenResult['oauth_token_secret']!;
      
      // Step 2: Direct user to authorize
      final authUrl = Uri.parse(
        '${_twitter1Config.authorizeUrl}?oauth_token=$oauthToken'
      );
      
      // Start local server and open browser
      final verifier = await _performOAuth1Flow(authUrl, oauthToken);
      if (verifier == null) {
        debugPrint('Failed to get OAuth verifier');
        return null;
      }
      
      // Step 3: Exchange for access token
      final accessTokenResult = await _getTwitterAccessToken(
        oauthToken,
        oauthTokenSecret,
        verifier,
      );
      if (accessTokenResult == null) {
        debugPrint('Failed to get access token');
        return null;
      }
      
      final accessToken = accessTokenResult['oauth_token']!;
      final accessTokenSecret = accessTokenResult['oauth_token_secret']!;
      final userId = accessTokenResult['user_id'];
      final screenName = accessTokenResult['screen_name'];
      
      // Get full user info
      final userInfo = await _getTwitterUserInfo1a(accessToken, accessTokenSecret);
      
      return SocialAccount(
        platform: 'twitter',
        username: '@${screenName ?? userId ?? 'unknown'}',
        displayName: userInfo?['name'] ?? screenName ?? 'Twitter User',
        avatarUrl: userInfo?['profile_image_url_https'],
        accessToken: accessToken,
        accessTokenSecret: accessTokenSecret,
        refreshToken: null, // OAuth 1.0a doesn't use refresh tokens
        expiresAt: null, // OAuth 1.0a tokens don't expire
        connectedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Twitter OAuth 1.0a error: $e');
      return null;
    }
  }
  
  /// Get request token from Twitter
  Future<Map<String, String>?> _getTwitterRequestToken() async {
    try {
      final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final nonce = _generateNonce();
      
      final params = {
        'oauth_callback': _twitter1Config.callbackUrl,
        'oauth_consumer_key': _twitter1Config.consumerKey,
        'oauth_nonce': nonce,
        'oauth_signature_method': 'HMAC-SHA1',
        'oauth_timestamp': timestamp,
        'oauth_version': '1.0',
      };
      
      final signature = _generateOAuth1Signature(
        'POST',
        _twitter1Config.requestTokenUrl,
        params,
        _twitter1Config.consumerSecret,
        '', // No token secret yet
      );
      
      params['oauth_signature'] = signature;
      
      final authHeader = _buildOAuth1Header(params);
      
      final response = await http.post(
        Uri.parse(_twitter1Config.requestTokenUrl),
        headers: {'Authorization': authHeader},
      );
      
      if (response.statusCode == 200) {
        return Uri.splitQueryString(response.body);
      } else {
        debugPrint('Request token failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Request token error: $e');
      return null;
    }
  }
  
  /// Exchange request token for access token
  Future<Map<String, String>?> _getTwitterAccessToken(
    String oauthToken,
    String oauthTokenSecret,
    String verifier,
  ) async {
    try {
      final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final nonce = _generateNonce();
      
      final params = {
        'oauth_consumer_key': _twitter1Config.consumerKey,
        'oauth_nonce': nonce,
        'oauth_signature_method': 'HMAC-SHA1',
        'oauth_timestamp': timestamp,
        'oauth_token': oauthToken,
        'oauth_verifier': verifier,
        'oauth_version': '1.0',
      };
      
      final signature = _generateOAuth1Signature(
        'POST',
        _twitter1Config.accessTokenUrl,
        params,
        _twitter1Config.consumerSecret,
        oauthTokenSecret,
      );
      
      params['oauth_signature'] = signature;
      
      final authHeader = _buildOAuth1Header(params);
      
      final response = await http.post(
        Uri.parse(_twitter1Config.accessTokenUrl),
        headers: {'Authorization': authHeader},
      );
      
      if (response.statusCode == 200) {
        return Uri.splitQueryString(response.body);
      } else {
        debugPrint('Access token failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Access token error: $e');
      return null;
    }
  }
  
  /// Get Twitter user info using OAuth 1.0a
  Future<Map<String, dynamic>?> _getTwitterUserInfo1a(
    String accessToken,
    String accessTokenSecret,
  ) async {
    try {
      final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final nonce = _generateNonce();
      final url = 'https://api.twitter.com/1.1/account/verify_credentials.json';
      
      final params = {
        'oauth_consumer_key': _twitter1Config.consumerKey,
        'oauth_nonce': nonce,
        'oauth_signature_method': 'HMAC-SHA1',
        'oauth_timestamp': timestamp,
        'oauth_token': accessToken,
        'oauth_version': '1.0',
      };
      
      final signature = _generateOAuth1Signature(
        'GET',
        url,
        params,
        _twitter1Config.consumerSecret,
        accessTokenSecret,
      );
      
      params['oauth_signature'] = signature;
      
      final authHeader = _buildOAuth1Header(params);
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': authHeader},
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Twitter user info error: $e');
      return null;
    }
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
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  }

  /// Perform the OAuth 1.0a flow: start local server, open browser, wait for callback
  Future<String?> _performOAuth1Flow(Uri authUrl, String expectedToken) async {
    final completer = Completer<String?>();
    
    try {
      // Start local HTTP server for callback
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _callbackPort);
      
      // Listen for the callback
      _server!.listen((request) async {
        if (request.uri.path == '/callback') {
          final oauthToken = request.uri.queryParameters['oauth_token'];
          final oauthVerifier = request.uri.queryParameters['oauth_verifier'];
          final denied = request.uri.queryParameters['denied'];
          
          // Send response to browser
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_getCallbackHtml(denied == null && oauthVerifier != null));
          await request.response.close();
          
          // Verify token and return verifier
          if (denied != null) {
            completer.complete(null);
          } else if (oauthToken != expectedToken) {
            debugPrint('OAuth token mismatch');
            completer.complete(null);
          } else {
            completer.complete(oauthVerifier);
          }
          
          // Close server after handling callback
          await _server?.close();
          _server = null;
        }
      });

      // Open browser for authentication
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open browser for authentication');
      }

      // Wait for callback with timeout
      final verifier = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          _server?.close();
          _server = null;
          return null;
        },
      );

      return verifier;
    } catch (e) {
      debugPrint('OAuth 1.0a flow error: $e');
      await _server?.close();
      _server = null;
      return null;
    }
  }

  /// Authenticate with LinkedIn using OAuth 2.0
  /// NOTE: LinkedIn integration is temporarily disabled until we have valid API credentials
  Future<SocialAccount?> authenticateLinkedIn() async {
    // LinkedIn integration coming soon - need to set up company page for API access
    throw Exception('LinkedIn integration coming soon! We are setting up API access.');
    
    // ignore: dead_code
    try {
      final state = _generateState();

      // Build authorization URL
      final authUrl = Uri.parse(_linkedInConfig.authorizationEndpoint).replace(
        queryParameters: {
          'response_type': 'code',
          'client_id': _linkedInConfig.clientId,
          'redirect_uri': _linkedInConfig.redirectUri,
          'scope': _linkedInConfig.scopes.join(' '),
          'state': state,
        },
      );

      // Start local server and open browser
      final code = await _performOAuthFlow(authUrl, state);
      if (code == null) return null;

      // Exchange code for tokens
      final tokenResponse = await _exchangeCodeForToken(
        config: _linkedInConfig,
        code: code,
        usePkce: false,
      );

      if (tokenResponse == null) return null;

      // Get user info from LinkedIn
      final userInfo = await _getLinkedInUserInfo(tokenResponse['access_token']);
      if (userInfo == null) return null;

      return SocialAccount(
        platform: 'linkedin',
        username: userInfo['sub'] ?? userInfo['email'] ?? '',
        displayName: userInfo['name'] ?? 'LinkedIn User',
        avatarUrl: userInfo['picture'],
        accessToken: tokenResponse['access_token'],
        refreshToken: tokenResponse['refresh_token'],
        expiresAt: tokenResponse['expires_in'] != null
            ? DateTime.now().add(Duration(seconds: tokenResponse['expires_in']))
            : null,
        connectedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('LinkedIn OAuth error: $e');
      return null;
    }
  }

  /// Authenticate with Reddit using OAuth 2.0
  ///
  /// Uses a local callback server (http://localhost:8642/callback).
  /// Requests a refresh token via duration=permanent when possible.
  Future<SocialAccount?> authenticateReddit() async {
    // Reddit integration coming soon - API keys are pending provisioning
    throw Exception('Reddit integration coming soon! We are setting up API access.');
    
    // ignore: dead_code
    try {
      final state = _generateState();

      final authUrl = Uri.parse(_redditConfig.authorizationEndpoint).replace(
        queryParameters: {
          'client_id': _redditConfig.clientId,
          'response_type': 'code',
          'state': state,
          'redirect_uri': _redditConfig.redirectUri,
          'duration': 'permanent',
          'scope': _redditConfig.scopes.join(' '),
        },
      );

      final code = await _performOAuthFlow(authUrl, state);
      if (code == null) return null;

      final tokenResponse = await _exchangeRedditCodeForToken(code: code);
      if (tokenResponse == null) return null;

      final accessToken = tokenResponse['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) return null;

      final userInfo = await _getRedditUserInfo(accessToken);
      if (userInfo == null) return null;

      final username = (userInfo['name'] as String?) ?? '';
      final displayName = username.isNotEmpty ? username : 'Reddit User';
      final avatarUrl = (userInfo['icon_img'] as String?)?.split('?').first;

      final expiresIn = tokenResponse['expires_in'];
      final expiresAt = expiresIn is int
          ? DateTime.now().add(Duration(seconds: expiresIn))
          : (expiresIn is String
              ? DateTime.now().add(Duration(seconds: int.tryParse(expiresIn) ?? 0))
              : null);

      return SocialAccount(
        platform: 'reddit',
        username: username,
        displayName: displayName,
        avatarUrl: avatarUrl,
        accessToken: accessToken,
        refreshToken: tokenResponse['refresh_token'] as String?,
        expiresAt: expiresAt,
        connectedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Reddit OAuth error: $e');
      return null;
    }
  }

  /// Perform the OAuth flow: start local server, open browser, wait for callback
  Future<String?> _performOAuthFlow(Uri authUrl, String expectedState) async {
    final completer = Completer<String?>();
    
    try {
      // Start local HTTP server for callback
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _callbackPort);
      
      // Listen for the callback
      _server!.listen((request) async {
        if (request.uri.path == '/callback') {
          final code = request.uri.queryParameters['code'];
          final state = request.uri.queryParameters['state'];
          final error = request.uri.queryParameters['error'];
          
          // Send response to browser
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_getCallbackHtml(error == null && code != null));
          await request.response.close();
          
          // Verify state and return code
          if (error != null) {
            completer.complete(null);
          } else if (state != expectedState) {
            debugPrint('OAuth state mismatch');
            completer.complete(null);
          } else {
            completer.complete(code);
          }
          
          // Close server after handling callback
          await _server?.close();
          _server = null;
        }
      });

      // Open browser for authentication
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open browser for authentication');
      }

      // Wait for callback with timeout
      final code = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          _server?.close();
          _server = null;
          return null;
        },
      );

      return code;
    } catch (e) {
      debugPrint('OAuth flow error: $e');
      await _server?.close();
      _server = null;
      return null;
    }
  }

  /// HTML page to show after OAuth callback
  String _getCallbackHtml(bool success) {
    final message = success
        ? 'Authentication successful! You can close this window.'
        : 'Authentication failed. Please try again.';
    final color = success ? '#4CAF50' : '#f44336';
    
    return '''
<!DOCTYPE html>
<html>
<head>
  <title>Kumiho Authentication</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      margin: 0;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: white;
    }
    .container {
      text-align: center;
      padding: 40px;
      background: rgba(255,255,255,0.1);
      border-radius: 16px;
      backdrop-filter: blur(10px);
    }
    .icon {
      font-size: 64px;
      margin-bottom: 20px;
    }
    h1 { margin: 0 0 10px 0; color: $color; }
    p { margin: 0; opacity: 0.8; }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">${success ? '✓' : '✗'}</div>
    <h1>${success ? 'Success!' : 'Failed'}</h1>
    <p>$message</p>
  </div>
  <script>setTimeout(() => window.close(), 3000);</script>
</body>
</html>
''';
  }

  /// Exchange authorization code for access token
  Future<Map<String, dynamic>?> _exchangeCodeForToken({
    required OAuthConfig config,
    required String code,
    String? codeVerifier,
    required bool usePkce,
  }) async {
    try {
      final body = <String, String>{
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': config.redirectUri,
        'client_id': config.clientId,
      };

      if (usePkce && codeVerifier != null) {
        body['code_verifier'] = codeVerifier;
      }

      if (!usePkce && config.clientSecret.isNotEmpty) {
        body['client_secret'] = config.clientSecret;
      }

      Map<String, String> headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      };

      final response = await http.post(
        Uri.parse(config.tokenEndpoint),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('Token exchange failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Token exchange error: $e');
      return null;
    }
  }

  /// Refresh an access token (only for LinkedIn, Twitter OAuth 1.0a tokens don't expire)
  Future<Map<String, dynamic>?> refreshToken({
    required String platform,
    required String refreshToken,
  }) async {
    // Twitter OAuth 1.0a tokens don't expire, no refresh needed
    if (platform == 'twitter') {
      return null;
    }
    
    final config = switch (platform) {
      'linkedin' => _linkedInConfig,
      'reddit' => _redditConfig,
      _ => null,
    };

    if (config == null) return null;

    try {
      if (platform == 'reddit') {
        return _refreshRedditToken(refreshToken: refreshToken);
      }

      final body = <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': config.clientId,
      };

      if (config.clientSecret.isNotEmpty) {
        body['client_secret'] = config.clientSecret;
      }

      Map<String, String> headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      };

      final response = await http.post(
        Uri.parse(config.tokenEndpoint),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Token refresh error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _exchangeRedditCodeForToken({
    required String code,
  }) async {
    try {
      final basic = base64Encode(utf8.encode('${_redditConfig.clientId}:${_redditConfig.clientSecret}'));
      final response = await http.post(
        Uri.parse(_redditConfig.tokenEndpoint),
        headers: {
          'Authorization': 'Basic $basic',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
          'User-Agent': 'KumihoAssetBrowser/1.0 (by kumihoclouds)',
        },
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': _redditConfig.redirectUri,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }

      debugPrint('Reddit token exchange failed: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Reddit token exchange error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _refreshRedditToken({
    required String refreshToken,
  }) async {
    try {
      final basic = base64Encode(utf8.encode('${_redditConfig.clientId}:${_redditConfig.clientSecret}'));
      final response = await http.post(
        Uri.parse(_redditConfig.tokenEndpoint),
        headers: {
          'Authorization': 'Basic $basic',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
          'User-Agent': 'KumihoAssetBrowser/1.0 (by kumihoclouds)',
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      debugPrint('Reddit token refresh failed: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Reddit token refresh error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getRedditUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://oauth.reddit.com/api/v1/me'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'User-Agent': 'KumihoAssetBrowser/1.0 (by kumihoclouds)',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      debugPrint('Reddit user info failed: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Reddit user info error: $e');
      return null;
    }
  }

  /// Get LinkedIn user info using OpenID Connect
  Future<Map<String, dynamic>?> _getLinkedInUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.linkedin.com/v2/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('LinkedIn user info error: $e');
      return null;
    }
  }

  /// Generate a random state parameter
  String _generateState() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Clean up resources
  void dispose() {
    _server?.close();
    _server = null;
  }
}
