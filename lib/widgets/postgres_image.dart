import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Loads a private driver document through a short-lived Supabase signed URL.
/// The database stores only "pg://<object-path>", never a permanent public URL.
class PostgresImage extends StatefulWidget {
  final String pgUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;

  const PostgresImage({
    super.key,
    required this.pgUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  @override
  State<PostgresImage> createState() => _PostgresImageState();
}

class _PostgresImageState extends State<PostgresImage> {
  late Future<String> _signedUrl;

  @override
  void initState() {
    super.initState();
    _signedUrl = _createSignedUrl(widget.pgUrl);
  }

  @override
  void didUpdateWidget(PostgresImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pgUrl != widget.pgUrl) {
      _signedUrl = _createSignedUrl(widget.pgUrl);
    }
  }

  Future<String> _createSignedUrl(String reference) async {
    if (!reference.startsWith('pg://')) {
      throw const FormatException('Unsupported private document reference');
    }
    final path = reference.substring('pg://'.length).trim();
    final segments = path.split('/');
    if (path.isEmpty || segments.length < 2 ||
        segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FormatException('Invalid private document path');
    }
    return Supabase.instance.client.storage
        .from('driver-documents')
        .createSignedUrl(path, 300);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _signedUrl,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: widget.placeholder ??
                const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) return _buildError();
        return Image.network(
          snapshot.data!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (context, error, stackTrace) => _buildError(),
        );
      },
    );
  }

  Widget _buildError() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.black12,
      alignment: Alignment.center,
      child: widget.placeholder ??
          const Icon(Icons.broken_image_outlined,
              color: Colors.white24, size: 40),
    );
  }
}
