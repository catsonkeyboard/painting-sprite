import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:painting_sprite/models/stroke.dart';
import 'package:painting_sprite/painting/canvas_controller.dart';
import 'package:painting_sprite/screens/color_screen.dart';
import 'package:painting_sprite/services/ai_keys.dart';
import 'package:painting_sprite/services/artwork_store.dart';

/// 本轮 BUG 修复的回归测试。
void main() {
  group('CanvasController 修复项', () {
    test('新笔画落笔清空重做栈（撤销掉的笔画不得复活）', () {
      final c = CanvasController();
      c.beginStroke(const Offset(0, 0), color: Colors.red, width: 8);
      c.endStroke();
      c.beginStroke(const Offset(5, 5), color: Colors.blue, width: 8);
      c.endStroke();

      c.undo(); // 撤销第二笔
      expect(c.canRedo, isTrue);

      // 画新的一笔 → redo 栈必须作废
      c.beginStroke(const Offset(9, 9), color: Colors.green, width: 8);
      expect(c.canRedo, isFalse, reason: '落笔后重做历史已污染');
      c.endStroke();

      c.redo(); // no-op
      expect(c.strokes.length, 2);
    });

    test('笔迹抽稀：重复点不膨胀点列表', () {
      final s = Stroke(color: Colors.red, width: 8);
      s.addPoint(const Offset(10, 10));
      s.addPoint(const Offset(10.2, 10.1)); // 距离 < 1.0，应被丢弃
      s.addPoint(const Offset(12, 12));
      expect(s.pointCount, 2);
    });

    test('笔画历史上限 200（防内存无界）', () {
      final c = CanvasController();
      for (var i = 0; i < CanvasController.maxStrokes + 10; i++) {
        c.beginStroke(Offset(i.toDouble(), 0), color: Colors.red, width: 8);
        c.endStroke();
      }
      expect(c.strokes.length, CanvasController.maxStrokes);
    });
  });

  group('AiKeys 修复项', () {
    test('空字符串密钥视为未配置（照抄 example 不应发真请求）', () {
      final keys = AiKeys.fromJson('''
        {"doubao_api_key": "", "llm_api_key": "",
         "kling_access_key": "", "kling_secret_key": ""}
      ''');
      expect(keys.hasAsr, isFalse);
      expect(keys.hasImage, isFalse);
      expect(keys.hasLlm, isFalse);
      expect(keys.hasVideo, isFalse);
    });

    test('非空密钥正常识别', () {
      final keys = AiKeys.fromJson('{"llm_api_key": "sk-123"}');
      expect(keys.hasLlm, isTrue);
      expect(keys.hasAsr, isFalse);
    });

    test('toJson/fromJson 往返一致（应用内配置持久化的基础）', () {
      final keys = AiKeys(
        doubaoApiKey: 'sk-1',
        doubaoAsrModel: 'ep-1',
        llmModel: 'deepseek-chat',
      );
      final back = AiKeys.fromJson(jsonEncode(keys.toJson()));
      expect(back.doubaoApiKey, 'sk-1');
      expect(back.doubaoAsrModel, 'ep-1');
      expect(back.hasAsr, isTrue);
      expect(back.hasImage, isTrue);
      expect(back.hasVideo, isTrue, reason: '一套 Key：豆包 Key 在即视频走 Seedance');
      expect(back.llmModel, 'deepseek-chat');
    });

    test('LLM 一套 Key 回落：llm 留空 + 豆包 Key → 方舟豆包模型', () {
      final keys = AiKeys.fromJson('{"doubao_api_key": "ark-1"}');
      expect(keys.hasLlm, isTrue);
      expect(keys.llmApiKeyEffective, 'ark-1');
      expect(keys.llmBaseUrlEffective, contains('volces.com'));
      expect(keys.llmModelEffective, startsWith('doubao-'));
    });

    test('LLM 独立配置：保持原智谱默认（向后兼容）', () {
      final keys = AiKeys.fromJson('{"llm_api_key": "glm-1"}');
      expect(keys.llmApiKeyEffective, 'glm-1');
      expect(keys.llmBaseUrlEffective, contains('bigmodel'));
      expect(keys.llmModelEffective, 'glm-4-flash');
    });

    test('LLM 防误配：base 指向他厂但没填 llm Key → 不复用豆包 Key（Mock）', () {
      final keys = AiKeys.fromJson(
          '{"doubao_api_key": "ark-1", "llm_base_url": "https://api.deepseek.com/v1"}');
      expect(keys.llmApiKeyEffective, isNull,
          reason: '不能把方舟 Key 发给 DeepSeek');
      expect(keys.hasLlm, isFalse);
      // 显式指向方舟时允许回落
      final ark = AiKeys.fromJson(
          '{"doubao_api_key": "ark-1", "llm_base_url": "https://ark.cn-beijing.volces.com/api/v3"}');
      expect(ark.llmApiKeyEffective, 'ark-1');
      expect(ark.hasLlm, isTrue);
    });

    test('ASR 半配置守卫：密钥在但模型仍是占位值 → 按未配置处理', () {
      // 照抄 example 模板（模型名未改）——不应发起注定失败的真请求
      final half = AiKeys.fromJson(
        '{"doubao_api_key": "sk-x", "doubao_asr_model": "doubao-speech-to-text"}');
      expect(half.hasAsr, isFalse);
      // 图像能力共用密钥、模型未被标记为占位，不受影响
      expect(half.hasImage, isTrue);

      // 空模型名同样视为半配置
      final empty = AiKeys.fromJson(
        '{"doubao_api_key": "sk-x", "doubao_asr_model": ""}');
      expect(empty.hasAsr, isFalse);

      // 填了控制台真实模型/接入点 ID → 正常启用
      final ok = AiKeys.fromJson(
        '{"doubao_api_key": "sk-x", "doubao_asr_model": "ep-2026xxxx"}');
      expect(ok.hasAsr, isTrue);
    });
  });

  group('LineArtLibrary 同义词匹配', () {
    test('孩子口语化表达也能命中内置库', () {
      expect(LineArtLibrary.match('我想要小白兔')?.$2, '兔子');
      expect(LineArtLibrary.match('画一个霸王龙')?.$2, '恐龙');
      expect(LineArtLibrary.match('小猫咪')?.$2, '小猫');
      expect(LineArtLibrary.match('我的家')?.$2, '房子');
    });

    test('库外词不命中（走云端生成）', () {
      expect(LineArtLibrary.match('挖掘机'), isNull);
      expect(LineArtLibrary.match(''), isNull);
    });
  });

  group('ArtworkStore 路径解析', () {
    test('Windows 反斜杠路径也能解析出 id', () {
      expect(
        ArtworkStore.idFromPngPath(r'C:\docs\artworks\1730000000000.png'),
        '1730000000000',
      );
      expect(
        ArtworkStore.idFromPngPath('/data/artworks/1730000000001.png'),
        '1730000000001',
      );
    });
  });
}
