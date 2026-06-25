// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants/firebase_config.dart';

/// Control Plane service for Kumiho Browser
///
/// Handles communication with the Kumiho control plane for:
/// - Token exchange (Firebase ID token -> Control Plane JWT)
/// - Tenant discovery and routing
class ControlPlaneService {
  ControlPlaneService({
    http.Client? httpClient,
    String? controlPlaneUrl,
  })  : _client = httpClient ?? http.Client(),
        _baseUrl = controlPlaneUrl ?? KumihoConfig.controlPlaneUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Exchange Firebase ID token for Control Plane JWT
  ///
  /// Returns a [ControlPlaneToken] containing the JWT and metadata,
  /// or throws [ControlPlaneException] on failure.
  Future<ControlPlaneToken> exchangeToken(String firebaseIdToken) async {
    final url = Uri.parse('$_baseUrl/api/control-plane/token');

    try {
      final response = await _client.post(
        url,
        headers: {
          'Authorization': 'Bearer $firebaseIdToken',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        final body = _tryParseJson(response.body);
        final message = body?['error'] ?? body?['message'] ?? response.body;
        throw ControlPlaneException(
          'Token exchange failed: $message',
          statusCode: response.statusCode,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ControlPlaneToken.fromJson(data);
    } on ControlPlaneException {
      rethrow;
    } catch (e) {
      throw ControlPlaneException('Token exchange failed: $e');
    }
  }

  /// Discover tenant routing information
  ///
  /// Returns [DiscoveryRecord] with data plane URL and tenant info.
  Future<DiscoveryRecord> discoverTenant(
    String firebaseIdToken, {
    String? tenantHint,
  }) async {
    final url = Uri.parse('$_baseUrl/api/discovery/tenant');

    try {
      final body = <String, dynamic>{};
      if (tenantHint != null) {
        body['tenant_hint'] = tenantHint;
      }

      final response = await _client.post(
        url,
        headers: {
          'Authorization': 'Bearer $firebaseIdToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        final data = _tryParseJson(response.body);
        final message = data?['error'] ?? data?['message'] ?? response.body;
        throw ControlPlaneException(
          'Discovery failed: $message',
          statusCode: response.statusCode,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return DiscoveryRecord.fromJson(data);
    } on ControlPlaneException {
      rethrow;
    } catch (e) {
      throw ControlPlaneException('Discovery failed: $e');
    }
  }

  /// Discover public tenant endpoint for anonymous browsing
  ///
  /// Returns [DiscoveryRecord] with data plane URL for public access.
  /// This doesn't require authentication - only works for public tenants.
  /// Uses the same /api/discovery/tenant endpoint but without auth token.
  Future<DiscoveryRecord> discoverPublicTenant(String tenantId) async {
    final url = Uri.parse('$_baseUrl/api/discovery/tenant');

    try {
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'tenant_hint': tenantId}),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        final data = _tryParseJson(response.body);
        final message = data?['error'] ?? data?['message'] ?? response.body;
        throw ControlPlaneException(
          'Public discovery failed: $message',
          statusCode: response.statusCode,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return DiscoveryRecord.fromJson(data);
    } on TimeoutException {
      throw ControlPlaneException('Public discovery failed: timeout (url=$url)');
    } on ControlPlaneException {
      rethrow;
    } catch (e) {
      throw ControlPlaneException('Public discovery failed: $e');
    }
  }

  Map<String, dynamic>? _tryParseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}

/// Control Plane JWT token with metadata
class ControlPlaneToken {
  const ControlPlaneToken({
    required this.token,
    required this.expiresAt,
    this.tenantId,
    this.tenantSlug,
  });

  factory ControlPlaneToken.fromJson(Map<String, dynamic> json) {
    return ControlPlaneToken(
      token: json['token'] as String,
      expiresAt: (json['expires_at'] as num).toInt(),
      tenantId: json['tenant_id'] as String?,
      tenantSlug: json['tenant_slug'] as String?,
    );
  }

  /// The Control Plane JWT
  final String token;

  /// Unix timestamp when the token expires
  final int expiresAt;

  /// Tenant ID (if available)
  final String? tenantId;

  /// Tenant slug (if available)
  final String? tenantSlug;

  /// Whether the token is still valid
  bool get isValid {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now < expiresAt;
  }

  /// Time until expiration
  Duration get timeUntilExpiry {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final remaining = expiresAt - now;
    return Duration(seconds: remaining > 0 ? remaining : 0);
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'expires_at': expiresAt,
        if (tenantId != null) 'tenant_id': tenantId,
        if (tenantSlug != null) 'tenant_slug': tenantSlug,
      };
}

/// Discovery record with tenant routing information
class DiscoveryRecord {
  const DiscoveryRecord({
    required this.tenantId,
    this.tenantName,
    required this.roles,
    required this.region,
    required this.cacheControl,
    this.guardrails,
  });

  factory DiscoveryRecord.fromJson(Map<String, dynamic> json) {
    return DiscoveryRecord(
      tenantId: json['tenant_id'] as String,
      tenantName: json['tenant_name'] as String?,
      roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? [],
      region: RegionRouting.fromJson(json['region'] as Map<String, dynamic>),
      cacheControl:
          CacheControl.fromJson(json['cache_control'] as Map<String, dynamic>),
      guardrails: json['guardrails'] as Map<String, dynamic>?,
    );
  }

  final String tenantId;
  final String? tenantName;
  final List<String> roles;
  final RegionRouting region;
  final CacheControl cacheControl;
  final Map<String, dynamic>? guardrails;

  /// Data plane server URL for gRPC connections
  String get serverUrl => region.serverUrl;

  /// gRPC authority header (if different from server URL)
  String? get grpcAuthority => region.grpcAuthority;

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        if (tenantName != null) 'tenant_name': tenantName,
        'roles': roles,
        'region': region.toJson(),
        'cache_control': cacheControl.toJson(),
        if (guardrails != null) 'guardrails': guardrails,
      };
}

/// Region routing information
class RegionRouting {
  const RegionRouting({
    required this.regionCode,
    required this.serverUrl,
    this.grpcAuthority,
  });

  factory RegionRouting.fromJson(Map<String, dynamic> json) {
    return RegionRouting(
      regionCode: json['region_code'] as String,
      serverUrl: json['server_url'] as String,
      grpcAuthority: json['grpc_authority'] as String?,
    );
  }

  final String regionCode;
  final String serverUrl;
  final String? grpcAuthority;

  Map<String, dynamic> toJson() => {
        'region_code': regionCode,
        'server_url': serverUrl,
        if (grpcAuthority != null) 'grpc_authority': grpcAuthority,
      };
}

/// Cache control metadata from discovery
class CacheControl {
  const CacheControl({
    required this.issuedAt,
    required this.refreshAt,
    required this.expiresAt,
    required this.expiresInSeconds,
    required this.refreshAfterSeconds,
  });

  factory CacheControl.fromJson(Map<String, dynamic> json) {
    return CacheControl(
      issuedAt: DateTime.parse(json['issued_at'] as String),
      refreshAt: DateTime.parse(json['refresh_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      expiresInSeconds: (json['expires_in_seconds'] as num).toInt(),
      refreshAfterSeconds: (json['refresh_after_seconds'] as num).toInt(),
    );
  }

  final DateTime issuedAt;
  final DateTime refreshAt;
  final DateTime expiresAt;
  final int expiresInSeconds;
  final int refreshAfterSeconds;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get shouldRefresh => DateTime.now().isAfter(refreshAt);

  Map<String, dynamic> toJson() => {
        'issued_at': issuedAt.toIso8601String(),
        'refresh_at': refreshAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'expires_in_seconds': expiresInSeconds,
        'refresh_after_seconds': refreshAfterSeconds,
      };
}

/// Exception for control plane errors
class ControlPlaneException implements Exception {
  const ControlPlaneException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ControlPlaneException: $message';
}
