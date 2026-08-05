import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sta/widgets/postgres_image.dart';
import 'profile_image_web_stub.dart'
    if (dart.library.js_interop) 'profile_image_web.dart' as web_img;

class ProfileImageWidget extends StatelessWidget {
  final String? imageUrl;
  final String? name;
  final double radius;
  final double? iconSize;
  final BoxFit fit;
  final Uint8List? imageBytes;

  const ProfileImageWidget({
    super.key,
    required this.imageUrl,
    this.name,
    this.radius = 25,
    this.iconSize,
    this.fit = BoxFit.cover,
    this.imageBytes,
  });

  @override
  Widget build(BuildContext context) {
    if (imageBytes != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.black26,
        child: ClipOval(
          child: Image.memory(
            imageBytes!,
            width: radius * 2,
            height: radius * 2,
            fit: fit,
          ),
        ),
      );
    }

    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder();
    }

    // WEB LOGIC: Use PostgresImage for pg:// URLs, otherwise use standard web image
    if (kIsWeb) {
      if (imageUrl!.startsWith('pg://')) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: Colors.black26,
          child: ClipOval(
            child: PostgresImage(
              pgUrl: imageUrl!,
              width: radius * 2,
              height: radius * 2,
              fit: fit,
              placeholder: _buildPlaceholder(),
            ),
          ),
        );
      }
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.black26,
        child: ClipOval(
          child: SizedBox(
            width: radius * 2,
            height: radius * 2,
            child: web_img.buildWebImage(
              url: imageUrl!,
              radius: radius,
              fit: fit,
              placeholder: _buildPlaceholder(),
            ),
          ),
        ),
      );
    }

    // MOBILE LOGIC
    if (imageUrl!.startsWith('pg://')) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.black26,
        child: ClipOval(
          child: PostgresImage(
            pgUrl: imageUrl!,
            width: radius * 2,
            height: radius * 2,
            fit: fit,
            placeholder: _buildPlaceholder(),
          ),
        ),
      );
    }

    // Handle local files on mobile
    if (!kIsWeb && !imageUrl!.startsWith('http')) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.black26,
        child: ClipOval(
          child: Image.file(
            File(imageUrl!),
            width: radius * 2,
            height: radius * 2,
            fit: fit,
            errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.black26,
      child: ClipOval(
        child: Image.network(
          imageUrl!,
          width: radius * 2,
          height: radius * 2,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.black26,
      child: name != null && name!.isNotEmpty
          ? Text(
              name![0].toUpperCase(),
              style: TextStyle(
                fontSize: radius * 0.8,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            )
          : Icon(
              Icons.person,
              size: iconSize ?? radius,
              color: Colors.white24,
            ),
    );
  }
}
