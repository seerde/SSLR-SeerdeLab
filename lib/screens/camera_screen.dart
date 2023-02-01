import 'dart:io';
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';

class Sign {
  final String name;
  final String score;

  const Sign({required this.name, required this.score});

  factory Sign.fromJson(Map<String, dynamic> json) {
    return Sign(name: json['name'], score: json['score']);
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen(
      {Key? key, required this.cameraController, required this.initCamera})
      : super(key: key);
  final CameraController? cameraController;
  final Future<void> Function({required bool frontCamera}) initCamera;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

enum TtsState { playing, stopped, paused, continued }

class _CameraScreenState extends State<CameraScreen> {
  XFile? imageFile;
  dynamic sign = const Sign(name: '', score: '').name;
  dynamic score = const Sign(name: '', score: '').score;

  late FlutterTts flutterTts;
  String? language;
  String? engine;
  double volume = 0.5;
  double pitch = 1.0;
  double rate = 0.5;
  bool isCurrentLanguageInstalled = false;

  String? _newVoiceText;
  int? _inputLength;

  TtsState ttsState = TtsState.stopped;

  get isPlaying => ttsState == TtsState.playing;
  get isStopped => ttsState == TtsState.stopped;
  get isPaused => ttsState == TtsState.paused;
  get isContinued => ttsState == TtsState.continued;

  bool get isIOS => !kIsWeb && Platform.isIOS;
  bool get isAndroid => !kIsWeb && Platform.isAndroid;
  bool get isWindows => !kIsWeb && Platform.isWindows;
  bool get isWeb => kIsWeb;

  bool recording = false;

  @override
  initState() {
    Timer mytimer = Timer.periodic(Duration(seconds: 3), (timer) {
      onTakePictureButtonPressed();
    });

    super.initState();
    initTts();
  }

  initTts() async {
    flutterTts = FlutterTts();

    // await flutterTts.setLanguage("ar-SA");
    if (await flutterTts.isLanguageAvailable("ar-SA")) {
      print("pass");
      await flutterTts.setLanguage("ar-SA");
    }

    _setAwaitOptions();

    if (isAndroid) {
      _getDefaultEngine();
      _getDefaultVoice();
    }

    flutterTts.setStartHandler(() {
      setState(() {
        print("Playing");
        ttsState = TtsState.playing;
      });
    });

    if (isAndroid) {
      flutterTts.setInitHandler(() {
        setState(() {
          print("TTS Initialized");
        });
      });
    }

    flutterTts.setCompletionHandler(() {
      setState(() {
        print("Complete");
        ttsState = TtsState.stopped;
      });
    });

    flutterTts.setCancelHandler(() {
      setState(() {
        print("Cancel");
        ttsState = TtsState.stopped;
      });
    });

    flutterTts.setPauseHandler(() {
      setState(() {
        print("Paused");
        ttsState = TtsState.paused;
      });
    });

    flutterTts.setContinueHandler(() {
      setState(() {
        print("Continued");
        ttsState = TtsState.continued;
      });
    });

    flutterTts.setErrorHandler((msg) {
      setState(() {
        print("error: $msg");
        ttsState = TtsState.stopped;
      });
    });
  }

  Future<dynamic> _getLanguages() async => await flutterTts.getLanguages;

  Future<dynamic> _getEngines() async => await flutterTts.getEngines;

  Future _getDefaultEngine() async {
    var engine = await flutterTts.getDefaultEngine;
    if (engine != null) {
      print(engine);
    }
  }

  Future _getDefaultVoice() async {
    var voice = await flutterTts.getDefaultVoice;
    if (voice != null) {
      print(voice);
    }
  }

  Future _speak() async {
    await flutterTts.setVolume(volume);
    await flutterTts.setSpeechRate(rate);
    await flutterTts.setPitch(pitch);

    if (_newVoiceText != null) {
      if (_newVoiceText!.isNotEmpty) {
        await flutterTts.speak(_newVoiceText!);
      }
    }
  }

  Future _setAwaitOptions() async {
    await flutterTts.awaitSpeakCompletion(true);
  }

  Future _stop() async {
    var result = await flutterTts.stop();
    if (result == 1) setState(() => ttsState = TtsState.stopped);
  }

  Future _pause() async {
    var result = await flutterTts.pause();
    if (result == 1) setState(() => ttsState = TtsState.paused);
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = widget.cameraController;

    if (cameraController == null || !cameraController.value.isInitialized) {
      print('Error: select a camera!');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      return null;
    }

    try {
      final XFile file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      print(e);
      return null;
    }
  }

  Future<Sign> sendPicture(XFile picture) async {
    setState(() {
      recording = !recording;
    });

    final response = await http.post(
      Uri.parse('http://192.168.1.105:5000/api/SSLR/predict'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'buffer': base64Encode(File(picture!.path).readAsBytesSync()),
      }),
    );
    var test = jsonDecode(response.body);
    print(test);
    if (response.statusCode == 200) {
      return Sign.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to get sign.');
    }
  }

  @override
  void dispose() {
    super.dispose();
    flutterTts.stop();
  }

  bool _isFrontCamera = true;

  void onTakePictureButtonPressed() {
    takePicture().then((XFile? file) async {
      if (mounted) {
        setState(() {
          imageFile = file;
        });
        if (file != null) {
          var result = await sendPicture(file);
          setState(() {
            sign = result.name.isNotEmpty ? result.name : sign;
            score = result.score.isNotEmpty ? result.score : score;
            _newVoiceText = result.name;
          });
          _speak();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        (widget.cameraController == null)
            ? Container(
                decoration: BoxDecoration(
                  color: Colors.blueGrey,
                  borderRadius: BorderRadius.circular(12),
                ),
              )
            : GestureDetector(
                onDoubleTap: () {
                  _isFrontCamera = !_isFrontCamera;
                  widget.initCamera(frontCamera: _isFrontCamera);
                },
                child: Builder(builder: (BuildContext builder) {
                  var camera = widget.cameraController!.value;
                  final fullSize = MediaQuery.of(context).size;
                  final size = Size(fullSize.width,
                      fullSize.height - (Platform.isIOS ? 90 : 60));
                  double scale;
                  try {
                    scale = size.aspectRatio * camera.aspectRatio;
                  } catch (_) {
                    scale = 1;
                  }
                  if (scale < 1) scale = 1 / scale;

                  return Transform.scale(
                    scale: scale,
                    child: CameraPreview(widget.cameraController!),
                  );
                }),
              ),
        Positioned(
          bottom: 15,
          child: Column(
            children: [
              !sign.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: const Color.fromARGB(185, 255, 255, 255),
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Text(
                                '$sign',
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Text(
                                '$score',
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Container(),
              GestureDetector(
                onTap: widget.cameraController != null &&
                        widget.cameraController!.value.isInitialized &&
                        !widget.cameraController!.value.isRecordingVideo
                    ? onTakePictureButtonPressed
                    : null,
                child: Image.asset(
                  'assets/images/camera_button.png',
                  scale: 4.3,
                ),
              )
            ],
          ),
        ),
      ],
    );
  }
}
