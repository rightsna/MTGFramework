import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_locale.dart';
import '../../controllers/store_shot_controller.dart';
import '../widgets/panel_controls.dart';
import 'source_actions.dart';

/// 우측 패널 "오브젝트" 탭: 여러 개의 추가 이미지(투명 컷아웃)를 등록하고 각자
/// 너비/위치/레이어를 조절한다. 상태는 [StoreShotController]가 소유하고, 이 탭은
/// 파일 선택·이미지 에디터(=BuildContext 단계)만 처리해 컨트롤러로 넘긴다.
class ObjectsTab extends StatelessWidget {
  const ObjectsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StoreShotController>();
    final busy = c.busy;

    Future<void> add() async {
      final picked = await pickImageFile();
      if (picked != null) {
        await c.addObject(picked.bytes, name: picked.name);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionTitle(tr(context, '오브젝트 (복수)', 'Objects (multiple)')),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : add,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(tr(context, '오브젝트 추가', 'Add object')),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr(context, '항목을 선택한 뒤 미리보기에서 드래그로 옮기고 모서리로 크기를 조절하세요.',
              'Select an item, then drag it in the preview and resize from a corner.'),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        if (c.objects.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr(context, '투명 PNG 컷아웃을 추가해 배경/폰과 함께 얹으세요.',
                  'Add transparent PNG cutouts to layer with the background/phone.'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          )
        else
          for (var i = 0; i < c.objects.length; i++)
            _ObjectCard(index: i),
      ],
    );
  }
}

/// 오브젝트 한 개 카드: 탭하면 선택(미리보기에서 이동/리사이즈). 썸네일·이름 +
/// 레이어(폰 앞/뒤) 토글 · 편집 · 삭제. 위치/크기는 미리보기 드래그로 조절한다.
class _ObjectCard extends StatelessWidget {
  const _ObjectCard({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StoreShotController>();
    if (index >= c.objects.length) return const SizedBox.shrink();
    final o = c.objects[index];
    final l = o.layout;
    final busy = c.busy;
    final selected = c.selectedObject == index;
    final primary = Theme.of(context).colorScheme.primary;

    Future<void> edit() async {
      final edited = await editImage(
          context, o.bytes, tr(context, '오브젝트 편집', 'Edit object'));
      if (edited != null) {
        await c.replaceObjectImage(index, edited,
            note: (ko: '오브젝트 편집 반영됨', en: 'Object edit applied'));
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => c.selectObject(selected ? null : index),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(o.bytes,
                    width: 36, height: 36, fit: BoxFit.contain),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${index + 1}. ${o.name}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ),
              IconButton(
                tooltip: l.inFront
                    ? tr(context, '폰 뒤로 보내기', 'Send behind phone')
                    : tr(context, '폰 앞으로 가져오기', 'Bring in front of phone'),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                    l.inFront ? Icons.flip_to_back : Icons.flip_to_front,
                    size: 18),
                onPressed: busy
                    ? null
                    : () => c.updateObjectLayout(
                        index, l.copyWith(inFront: !l.inFront)),
              ),
              IconButton(
                tooltip: tr(context, '이미지 에디터로 편집', 'Edit in Image Editor'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: busy ? null : edit,
              ),
              IconButton(
                tooltip: tr(context, '제거', 'Remove'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: busy ? null : () => c.removeObject(index),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
