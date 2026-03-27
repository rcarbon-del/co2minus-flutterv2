import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';

class CarbonEstimatorService {
  Interpreter? _gruInterpreter;
  Map<String, dynamic>? _lcaDatabase;
  Map<String, dynamic>? _scalerConfig;

  Future<void> initialize() async {
    try {
      final lcaString = await rootBundle.loadString('assets/flutter_lca_database.json');
      _lcaDatabase = json.decode(lcaString);

      final scalerString = await rootBundle.loadString('assets/flutter_scaler_config.json');
      _scalerConfig = json.decode(scalerString);

      _gruInterpreter = await Interpreter.fromAsset('assets/models/gru.tflite');
    } catch (e) {
      Fluttertoast.showToast(msg: "Failed to start Carbon Service: $e");
    }
  }

  Future<double?> estimateFootprint(String yoloClass, double weightKg) async {
    if (_gruInterpreter == null || _lcaDatabase == null || _scalerConfig == null) {
      Fluttertoast.showToast(msg: "Service not initialized. Please restart the app.");
      return null;
    }

    if (!_lcaDatabase!.containsKey(yoloClass)) {
      Fluttertoast.showToast(msg: "Class '$yoloClass' missing from database.");
      return null;
    }

    List<dynamic> baseLca = _lcaDatabase![yoloClass];

    List<double> actualLca = baseLca.map((val) => (val as double) * weightKg).toList();

    List<dynamic> scaleVals = _scalerConfig!['scale_vals'];
    List<dynamic> minOffsets = _scalerConfig!['min_offsets'];

    List<double> scaledLca = [];
    for (int i = 0; i < actualLca.length; i++) {
      double scaledValue = (actualLca[i] * scaleVals[i]) + minOffsets[i];
      scaledLca.add(scaledValue);
    }

    var inputTensor = [
      scaledLca.map((val) => [val]).toList()
    ];

    var outputTensor = List.filled(1 * 1, 0.0).reshape([1, 1]);

    try {
      _gruInterpreter!.run(inputTensor, outputTensor);

      double finalCarbonFootprint = outputTensor[0][0];
      return finalCarbonFootprint;

    } catch (e) {
      Fluttertoast.showToast(msg: "Inference failed: $e");
      return null;
    }
  }

  void dispose() {
    _gruInterpreter?.close();
  }
}