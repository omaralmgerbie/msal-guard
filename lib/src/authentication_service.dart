import 'dart:developer';

import 'package:msal_flutter/msal_flutter.dart';
import 'package:rxdart/rxdart.dart';

import './authentication_status.dart';

class AuthenticationService {
  /// Create a new authentication ser
  AuthenticationService(
      {required this.clientId,
      required this.defaultScopes,
      this.defaultAuthority,
      this.redirectUri,
      this.keychain,
      this.androidRedirectUri,
      this.iosRedirectUri,
      this.privateSession});

  final String clientId;
  final String? defaultAuthority;
  final String? redirectUri;
  final String? androidRedirectUri;
  final String? iosRedirectUri;
  final String? keychain;
  /// privateSession is set to true to request that the browser doesn’t share cookies or other browsing data between the authentication session and the user’s normal browser session. Whether the request is honored depends on the user’s default web browser. Safari always honors the request.
  /// The value of this property is false by default.
  final bool? privateSession;

  PublicClientApplication? pca;
  String? _currentAuthority;
  List<String> defaultScopes;

  // behavior subject
  final BehaviorSubject<AuthenticationStatus> _authenticationStatusSubject =
      BehaviorSubject<AuthenticationStatus>.seeded(AuthenticationStatus.none);

  /// Stream for updates to authentication status
  Stream<AuthenticationStatus> get authenticationStatus =>
      _authenticationStatusSubject.stream;

  /// Updates the authentication status
  void _updateStatus(AuthenticationStatus status) {
    var last = this._authenticationStatusSubject.value;
    if (status == last) {
      return;
    }
    _authenticationStatusSubject.add(status);
  }

  /// Initialisation function. Only to be called once on startup or first usage of auth service.
  /// @param authorityOverride A override for the authority to use while initiating.
  /// This should be used when user previously logged in using a different authority to null such
  /// as when signing in with different userflows, such as seperate flows for different social providers
  Future init() async {
    await _initPca(defaultAuthority);
    //store the default scopes for the app
    try {
      await acquireTokenSilently();
      _authenticationStatusSubject.add(AuthenticationStatus.authenticated);
    } on Exception catch(e) {
      log(e.toString());
      print(
          "Default init signin failed. USer not signed in to default authority.");
      _authenticationStatusSubject.add(AuthenticationStatus.unauthenticated);
    }
  }

  //initiate an authority
  Future _initPca(String? authority) async {
    _currentAuthority = authority;
    pca = await PublicClientApplication.createPublicClientApplication(
        this.clientId,
        authority: authority,
        redirectUri: this.redirectUri,
        androidRedirectUri: this.androidRedirectUri,
        iosRedirectUri: this.iosRedirectUri,
        keychain: this.keychain,
        privateSession: privateSession);
  }

  Future<String> acquireToken({List<String>? scopes}) async {
    try {
      _pcaInitializedGuard();
      var res = await pca!.acquireToken(scopes ?? defaultScopes);
      _updateStatus(AuthenticationStatus.authenticated);
      return res;
    } catch (e) {
      _updateStatus(AuthenticationStatus.unauthenticated);
      throw e;
    }
  }

  Future<String> acquireTokenSilently({List<String>? scopes}) async {
    try {
      _pcaInitializedGuard();
      var res = await pca!.acquireTokenSilent(scopes ?? defaultScopes);
      _updateStatus(AuthenticationStatus.authenticated);
      return res;
    } catch (e) {
      _updateStatus(AuthenticationStatus.unauthenticated);
      throw e;
    }
  }

  Future login({String? authorityOverride}) async {
    var authority = authorityOverride ?? defaultAuthority;

    try {
      // if override set, reinit with new authority
      if (pca == null || _currentAuthority != authority) {
        await _initPca(authority);
      }

      print("Logging in");
      _updateStatus(AuthenticationStatus.authenticating);
      await pca!.acquireToken(defaultScopes);
      _updateStatus(AuthenticationStatus.authenticated);
    } catch (e) {
      _updateStatus(AuthenticationStatus.failed);
      rethrow;
    }
  }

  Future logout({bool browserLogout = false}) async {
    try {
      await pca!.logout(browserLogout: browserLogout);
    } finally {
      _updateStatus(AuthenticationStatus.unauthenticated);
    }
  }

  void dispose() {
    _authenticationStatusSubject.close();
  }

  /// Ensures PublicClientApplication is initialized before it is used.
  void _pcaInitializedGuard() {
    if (pca == null) {
      throw new MsalException(
          "PublicClientApplication must be initialized before use.");
    }
  }
}
