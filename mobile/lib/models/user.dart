class User {
  User({
    required this.id,
    required this.email,
    required this.username,
    this.avatarUrl,
    required this.identityPublicKey,
  });

  final String id;
  final String email;
  final String username;
  final String? avatarUrl;
  final String identityPublicKey;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
      identityPublicKey: json['identity_public_key'] as String? ?? '',
    );
  }
}

class PublicUser {
  PublicUser({
    required this.id,
    required this.username,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String? avatarUrl;

  factory PublicUser.fromJson(Map<String, dynamic> json) {
    return PublicUser(
      id: json['id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
