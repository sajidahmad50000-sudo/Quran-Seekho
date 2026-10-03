import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:io';

const green = Color(0xFF0B6B4B);
const cream = Color(0xFFF8F2E6);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(QuranSeekho(prefs: prefs));
}

class QuranSeekho extends StatelessWidget {
  final SharedPreferences prefs;
  const QuranSeekho({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Quran Seekho',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: cream,
        colorScheme: ColorScheme.fromSeed(seedColor: green),
        appBarTheme: const AppBarTheme(
          backgroundColor: green,
          foregroundColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      home: HomePage(prefs: prefs),
    );
  }
}

class QuranData {
  final List<Map<String, dynamic>> surahs;

  QuranData(this.surahs);

  static Future<QuranData> load() async {
    final raw = await rootBundle.loadString(
      'assets/quran_uthmani.json',
    );
    final data = jsonDecode(raw) as Map<String, dynamic>;

    return QuranData(
      (data['surahs'] as List).cast<Map<String, dynamic>>(),
    );
  }
}

class OfflineAudioManager {
  static final OfflineAudioManager instance =
      OfflineAudioManager._();

  OfflineAudioManager._();

  final AudioPlayer player = AudioPlayer();
  int? currentSurah;

  String urlFor(int surah) =>
      'https://download.quranicaudio.com/quran/'
      'abdullaah_3awwaad_al-juhaynee/'
      '${surah.toString().padLeft(3, '0')}.mp3';

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/quran_audio');

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  Future<File> localFile(int surah) async {
    final dir = await _dir();
    return File(
      '${dir.path}/${surah.toString().padLeft(3, '0')}.mp3',
    );
  }

  Future<bool> isDownloaded(int surah) async {
    final file = await localFile(surah);

    if (!await file.exists()) {
      return false;
    }

    return (await file.length()) > 0;
  }

  Future<int> localSize(int surah) async {
    final file = await localFile(surah);

    return await file.exists()
        ? file.length()
        : 0;
  }

  Future<File> download(
    int surah, {
    void Function(int received, int total)? onProgress,
  }) async {
    final file = await localFile(surah);

    if (await isDownloaded(surah)) {
      onProgress?.call(
        await file.length(),
        await file.length(),
      );
      return file;
    }

    final temp = File('${file.path}.part');

    if (await temp.exists()) {
      await temp.delete();
    }

    final client = http.Client();

    try {
      final request = http.Request(
        'GET',
        Uri.parse(urlFor(surah)),
      );

      final response = await client
          .send(request)
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        throw Exception(
          'Audio download failed (${response.statusCode})',
        );
      }

      final total = response.contentLength ?? -1;
      var received = 0;

      final sink = temp.openWrite();

      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }

      if (received == 0) {
        throw Exception(
          'Audio file خالی موصول ہوئی۔',
        );
      }

      if (total > 0 && received != total) {
        throw Exception(
          'Audio download مکمل نہیں ہوئی۔ '
          'دوبارہ کوشش کریں۔',
        );
      }

      if (await file.exists()) {
        await file.delete();
      }

      await temp.rename(file.path);

      return file;
    } finally {
      client.close();
    }
  }
}
