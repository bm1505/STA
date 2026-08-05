import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/sound_service.dart';
import '../services/call_service.dart';
import '../providers/auth_provider.dart';
import '../utils/theme.dart';

class CallScreen extends StatefulWidget {
  final String channelId;
  final String remoteUserName;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.channelId,
    required this.remoteUserName,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late RtcEngine _engine;
  bool _localUserJoined = false;
  bool _remoteUserJoined = false;
  bool _muted = false;
  bool _speaker = true;
  bool _onHold = false;
  int _seconds = 0;
  Timer? _timer;
  StreamSubscription? _callSubscription;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // 1. Handle Permissions
    bool hasPermissions = await CallService.handlePermissions();
    if (!hasPermissions) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Microphone permission is required for calls")),
        );
        Navigator.pop(context);
      }
      return;
    }

    // 2. Init Agora
    await _initAgora();

    // 3. Start logic
    _startTimer();
    _listenToCallStatus();

    if (!widget.isIncoming) {
      // If we are the caller, notify the receiver via Firestore
      final auth = Provider.of<AuthProvider>(context, listen: false);
      CallService.updateCallStatus(
        widget.channelId,
        'ringing',
        callerName: auth.currentUser?.name ?? "User",
        callerId: auth.currentUser?.id,
      );
    }
  }

  void _listenToCallStatus() {
    _callSubscription =
        CallService.listenToCall(widget.channelId).listen((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return;

      final data = snapshot.data() as Map<String, dynamic>;
      
      // If call is ended in database, leave immediately
      if (data['activeCall'] == null) {
        _endCall(updateFirestore: false);
      }
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _localUserJoined) {
        setState(() {
          _seconds++;
        });
      }
    });
  }

  Future<void> _initAgora() async {
    _engine = createAgoraRtcEngine();
    await _engine.initialize(const RtcEngineContext(
      appId: CallService.appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint("local user ${connection.localUid} joined");
          if (mounted) {
            setState(() {
              _localUserJoined = true;
            });
            // Play ringback tone if we are the caller
            if (!widget.isIncoming) {
              SoundService.playRingback();
            } else {
              SoundService.playRingtone();
            }
          }
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("remote user $remoteUid joined");
          if (mounted) {
            setState(() {
              _remoteUserJoined = true;
            });
            // Stop ringing sound once connected
            SoundService.stopAll();
            // Mark call as ongoing
            CallService.updateCallStatus(widget.channelId, 'ongoing');
          }
        },
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          debugPrint("remote user $remoteUid left channel");
          _endCall(updateFirestore: true);
        },
        onError: (ErrorCodeType err, String msg) {
          debugPrint("Agora Error: $err, $msg");
        },
      ),
    );

    await _engine.enableAudio();
    await _engine.setEnableSpeakerphone(_speaker);
    
    await _engine.joinChannel(
      token: '',
      channelId: widget.channelId,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
      ),
    );
  }

  void _endCall({bool updateFirestore = true}) async {
    // 1. Close UI immediately for responsiveness
    if (mounted) {
      Navigator.pop(context);
    }

    // 2. Clean up in background
    _timer?.cancel();
    _callSubscription?.cancel();
    SoundService.stopAll();

    if (updateFirestore) {
      CallService.updateCallStatus(widget.channelId, null);
    }

    await _engine.leaveChannel();
    await _engine.release();
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
    });
    _engine.muteLocalAudioStream(_muted);
  }

  void _toggleSpeaker() {
    setState(() {
      _speaker = !_speaker;
    });
    _engine.setEnableSpeakerphone(_speaker);
  }

  void _toggleHold() {
    setState(() {
      _onHold = !_onHold;
    });
    // When on hold, we mute local audio and stop receiving remote audio
    _engine.muteLocalAudioStream(_onHold || _muted);
    _engine.muteAllRemoteAudioStreams(_onHold);
  }

  String _formatTime(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _engine.leaveChannel();
    _engine.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            CircleAvatar(
              radius: 50,
              backgroundColor: AppTheme.primaryGold.withValues(alpha: 0.1),
              child: const Icon(Icons.person,
                  size: 60, color: AppTheme.primaryGold),
            ),
            const SizedBox(height: 20),
            Text(
              widget.remoteUserName,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              !_localUserJoined 
                  ? "Connecting..." 
                  : (_remoteUserJoined ? _formatTime(_seconds) : "Ringing..."),
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCallOption(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    color: _muted ? Colors.white24 : Colors.white10,
                    onTap: _toggleMute,
                    label: "Mute",
                  ),
                  _buildCallOption(
                    icon: _onHold ? Icons.pause : Icons.play_arrow,
                    color: _onHold
                        ? Colors.orange.withValues(alpha: 0.3)
                        : Colors.white10,
                    onTap: _toggleHold,
                    label: "Hold",
                  ),
                  _buildCallOption(
                    icon: Icons.call_end,
                    color: Colors.red,
                    onTap: _endCall,
                    isLarge: true,
                  ),
                  _buildCallOption(
                    icon: _speaker ? Icons.volume_up : Icons.volume_off,
                    color: _speaker ? Colors.white24 : Colors.white10,
                    onTap: _toggleSpeaker,
                    label: "Speaker",
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallOption({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isLarge = false,
    String? label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.all(isLarge ? 20 : 15),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: isLarge ? 30 : 25),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}
