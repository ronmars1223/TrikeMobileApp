import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Audio format enum for easier format selection
enum AudioFormat { mp3, m4a, wav, aac }

class AudioRecorderHelper {
  static final AudioRecorder _recorder = AudioRecorder();
  static Timer? _recordingTimer;
  static bool _isRecording = false;
  static bool _autoStopped = false;
  static bool _forceRecordingCompletion = false;
  static String? _currentRecordingPath;
  static Directory? _recordingsDirectory;

  /// Initialize the recorder and create recordings directory in external storage
  static Future<void> initialize() async {
    try {
      // First request storage permission
      if (await Permission.storage.request().isGranted &&
          await Permission.manageExternalStorage.request().isGranted) {
        // Get the external storage directory
        Directory? externalDir;

        try {
          // Try to get the external storage directory first
          externalDir = await getExternalStorageDirectory();
        } catch (e) {
          print('Error getting external storage directory: $e');
        }

        if (externalDir == null) {
          // Fallback to application documents directory
          externalDir = await getApplicationDocumentsDirectory();
          print('Using app documents directory: ${externalDir.path}');
        } else {
          // Go up to the root of external storage
          String path = externalDir.path;
          List<String> pathSegments = path.split('/');
          // Find Android directory index in path
          int androidIndex = pathSegments.indexOf('Android');
          if (androidIndex != -1 && androidIndex > 0) {
            // Go up to the parent of Android directory (which should be the root of external storage)
            path = pathSegments.sublist(0, androidIndex).join('/');
            print('External storage root path: $path');
            externalDir = Directory(path);
          }
        }

        // Create a "Recordings" directory
        _recordingsDirectory = Directory('${externalDir.path}/Recordings');

        if (!await _recordingsDirectory!.exists()) {
          await _recordingsDirectory!.create(recursive: true);
          print('Created Recordings directory: ${_recordingsDirectory!.path}');
        }

        return;
      } else {
        print('Permission to access storage denied');
      }
    } catch (e) {
      print('Error initializing recorder storage: $e');
    }

    // Fallback to app documents directory if any error occurs
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _recordingsDirectory = Directory('${appDir.path}/Recordings');

      if (!await _recordingsDirectory!.exists()) {
        await _recordingsDirectory!.create(recursive: true);
        print(
          'Created fallback Recordings directory: ${_recordingsDirectory!.path}',
        );
      }
    } catch (e) {
      print('Error creating fallback directory: $e');
      // Last resort fallback
      final appDir = await getApplicationDocumentsDirectory();
      _recordingsDirectory = appDir;
    }
  }

  /// Alternative method to use specific public directory
  static Future<void> initializePublicDirectory() async {
    try {
      // Request required permissions
      var storageStatus = await Permission.storage.request();
      var externalStorageStatus =
          await Permission.manageExternalStorage.request();

      if (storageStatus.isGranted || externalStorageStatus.isGranted) {
        // Try to create directory in root of external storage
        try {
          // This is the path to the "Recordings" folder in the root of internal storage
          _recordingsDirectory = Directory('/storage/emulated/0/Recordings');

          if (!await _recordingsDirectory!.exists()) {
            await _recordingsDirectory!.create(recursive: true);
            print(
              'Created public Recordings directory: ${_recordingsDirectory!.path}',
            );
          }
          return;
        } catch (e) {
          print('Error creating public directory: $e');
        }
      }
    } catch (e) {
      print('Error setting up public directory: $e');
    }

    // If all fails, fall back to the original initialize method
    await initialize();
  }

  /// Get all saved recordings
  static Future<List<File>> getSavedRecordings() async {
    if (_recordingsDirectory == null) {
      await initialize();
    }

    try {
      final files = await _recordingsDirectory!.list().toList();
      return files
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.mp3') ||
                file.path.endsWith('.m4a') ||
                file.path.endsWith('.wav') ||
                file.path.endsWith('.aac'),
          )
          .toList();
    } catch (e) {
      print('Error getting saved recordings: $e');
      return [];
    }
  }

  /// Get the recordings directory path
  static String? getRecordingsDirectoryPath() {
    return _recordingsDirectory?.path;
  }

  /// Delete a recording file
  static Future<bool> deleteRecording(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        print('Deleted recording: $path');
        return true;
      }
    } catch (e) {
      print('Error deleting recording: $e');
    }
    return false;
  }

  /// Start recording audio with automatic stop after specified duration
  /// Returns the path to the recording file or null if failed
  static Future<String?> startRecording({
    int durationMinutes = 3,
    bool completeFullDuration = false,
    AudioFormat format = AudioFormat.mp3,
    String? customFilename,
  }) async {
    if (_isRecording) {
      print('Recording already in progress');
      return _currentRecordingPath;
    }

    if (_recordingsDirectory == null) {
      // Try to use the public directory method first
      await initializePublicDirectory();
    }

    _autoStopped = false;
    _forceRecordingCompletion = completeFullDuration;

    try {
      // Request microphone permission
      if (await Permission.microphone.request().isGranted) {
        if (await _recorder.hasPermission()) {
          // File extension based on format
          final extension = _getFileExtension(format);

          // Create filename with date and time for better organization
          final now = DateTime.now();
          final timestamp = now.millisecondsSinceEpoch;
          final dateStr =
              "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
          final timeStr =
              "${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}";

          final filename = customFilename ?? 'recording_${dateStr}_${timeStr}';
          final recordingPath =
              '${_recordingsDirectory!.path}/$filename$extension';

          _currentRecordingPath = recordingPath;

          // Configure audio format
          final config = _getRecordConfig(format);

          // Start recording
          await _recorder.start(config, path: recordingPath);

          _isRecording = true;
          print(
            'Recording started at: $_currentRecordingPath with format: ${format.toString()}',
          );

          // Schedule automatic stop after specified duration
          _recordingTimer?.cancel();
          _recordingTimer = Timer(Duration(minutes: durationMinutes), () async {
            if (await _recorder.isRecording()) {
              final stoppedPath = await _recorder.stop();
              _autoStopped = true;
              _isRecording = false;
              print(
                'Auto-stopped recording after $durationMinutes minutes at: $stoppedPath',
              );
            }
          });

          return _currentRecordingPath;
        }
      }
    } catch (e) {
      print('Error starting recording: $e');
      _currentRecordingPath = null;
    }

    return null;
  }

  /// Get file extension based on audio format
  static String _getFileExtension(AudioFormat format) {
    switch (format) {
      case AudioFormat.mp3:
        return '.mp3';
      case AudioFormat.wav:
        return '.wav';
      case AudioFormat.aac:
        return '.aac';
      case AudioFormat.m4a:
      default:
        return '.m4a';
    }
  }

  /// Get recording configuration based on audio format
  static RecordConfig _getRecordConfig(AudioFormat format) {
    switch (format) {
      case AudioFormat.mp3:
        return RecordConfig(
          encoder:
              AudioEncoder
                  .aacLc, // Using aacLc since mp3 might not be directly available
          bitRate: 128000, // 128 kbps
          sampleRate: 44100,
        );
      case AudioFormat.wav:
        return RecordConfig(
          encoder: AudioEncoder.pcm16bits, // For WAV
          bitRate: 768000, // High quality
          sampleRate: 44100,
        );
      case AudioFormat.aac:
        return RecordConfig(
          encoder: AudioEncoder.aacLc, // Using aacLc for AAC
          bitRate: 128000,
          sampleRate: 44100,
        );
      case AudioFormat.m4a:
      default:
        return RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        );
    }
  }

  /// Stop the current recording
  /// Returns the path to the recording file or null if failed
  /// If forceRecordingCompletion is true, this method will return the path but not actually stop recording
  static Future<String?> stopRecording({
    bool ignoreForceCompletion = false,
  }) async {
    if (!_isRecording) {
      print('No recording in progress');
      return null;
    }

    // If we're forcing the recording to complete and this isn't an override call
    if (_forceRecordingCompletion && !ignoreForceCompletion) {
      print(
        'Recording set to complete full duration, returning path without stopping',
      );
      return _currentRecordingPath;
    }

    try {
      if (await _recorder.isRecording()) {
        final path = await _recorder.stop();
        _isRecording = false;
        _recordingTimer?.cancel();
        print('Recording stopped at: $path');
        return path;
      }
    } catch (e) {
      print('Error stopping recording: $e');
    }

    return _currentRecordingPath;
  }

  /// Get the current recording path without stopping the recording
  static String? getRecordingPath() {
    return _currentRecordingPath;
  }

  /// Check if recording is in progress
  static Future<bool> isRecording() async {
    return _isRecording && await _recorder.isRecording();
  }

  /// Force stop any ongoing recording (to be called from app lifecycle methods)
  static Future<String?> forceStopRecording() async {
    return await stopRecording(ignoreForceCompletion: true);
  }

  /// Clean up resources when done with the recorder
  static void dispose() {
    _recordingTimer?.cancel();
    _recorder.dispose();
    _currentRecordingPath = null;
    _isRecording = false;
  }

  /// Check if recording was automatically stopped by the timer
  static bool wasAutoStopped() {
    return _autoStopped;
  }

  /// Get the duration for which the recording has been in progress
  static Duration getRecordingDuration() {
    if (!_isRecording || _currentRecordingPath == null) {
      return Duration.zero;
    }

    // Extract timestamp from filename
    try {
      final filenamePattern = RegExp(r'recording_(\d+)');
      final match = filenamePattern.firstMatch(_currentRecordingPath!);

      if (match != null && match.groupCount >= 1) {
        final timestamp = int.parse(match.group(1)!);
        final startTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        return DateTime.now().difference(startTime);
      }
    } catch (e) {
      print('Error calculating recording duration: $e');
    }

    return Duration.zero;
  }

  /// Get the audio file size in MB
  static Future<double> getFileSize(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.length();
        return bytes / (1024 * 1024); // Convert to MB
      }
    } catch (e) {
      print('Error getting file size: $e');
    }
    return 0.0;
  }
}
