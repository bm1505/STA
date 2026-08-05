import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'profile_image_web_stub.dart'
    if (dart.library.js_interop) 'profile_image_web.dart' as web_img;

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
  late String _timestamp;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    });
  }

  @override
  void didUpdateWidget(PostgresImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pgUrl != widget.pgUrl) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    String userId = "unknown";
    String fileType = "";
    
    try {
      final path = widget.pgUrl.replaceFirst("pg://", "");
      final parts = path.split("/");
      userId = parts[0];
      if (parts.length > 1) {
        String raw = parts[1].toLowerCase();
        if (raw.contains('license')) fileType = 'license';
        else if (raw.contains('insurance')) fileType = 'insurance';
        else if (raw.contains('national') || raw.contains('nida')) fileType = 'nida';
        else if (raw.contains('profile')) fileType = 'profile';
        else if (raw.contains('vehicle')) fileType = 'vehicle';
        else fileType = raw.split('_').first.split('.').first;
      }
    } catch (_) {}

    // ==========================================
    // BADILISHA HAPA: 
    // Ikiwa unatumia simu ya kweli, weka IP ya kompyuta yako hapa (mfano '192.168.1.10')
    // Ikiwa unatumia emulator, acha '10.0.2.2'
    String myComputerIP = "192.168.1.103";
    // ==========================================

    String baseUrl = kIsWeb ? 'http://localhost:3000/' : 'http://$myComputerIP:3000/';
    final String proxyUrl = '$baseUrl?userId=$userId&type=$fileType&t=$_timestamp';

    if (kIsWeb) {
      if (widget.width == null || widget.height == null) {
        return Image.network(
          proxyUrl,
          fit: widget.fit,
          errorBuilder: (context, error, stackTrace) => _buildError(),
          loadingBuilder: (context, child, loadingProgress) {
             if (loadingProgress == null) return child;
             return widget.placeholder ?? const Center(child: CircularProgressIndicator());
          },
        );
      }

      return Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        child: web_img.buildWebImage(
          url: proxyUrl,
          radius: 0,
          fit: widget.fit,
          placeholder: widget.placeholder,
        ),
      );
    }

    return Image.network(
      proxyUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      headers: const {"Keep-Alive": "timeout=5, max=1000"},
      errorBuilder: (context, error, stackTrace) {
        debugPrint("Image Load Error: $error");
        return _buildError();
      },
    );
  }

  Widget _buildError() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.black12,
      alignment: Alignment.center,
      child: widget.placeholder ?? const Icon(Icons.person, color: Colors.white24, size: 40),
    );
  }
}
