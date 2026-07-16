import 'package:flutter/material.dart';

import '../../services/api_service.dart';

/// 서버에 받아둔 LoRA 목록 다이얼로그 — 개별/전체 삭제(디스크 용량 관리).
Future<void> showLoraManager(BuildContext context, String baseUrl) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _LoraManagerDialog(baseUrl: baseUrl),
  );
}

class _LoraManagerDialog extends StatefulWidget {
  const _LoraManagerDialog({required this.baseUrl});
  final String baseUrl;

  @override
  State<_LoraManagerDialog> createState() => _LoraManagerDialogState();
}

class _LoraManagerDialogState extends State<_LoraManagerDialog> {
  List<LoraInfo> _items = const [];
  double _total = 0;
  bool _loading = true;
  String? _err;

  ApiService get _api => ApiService(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await _api.listLoras();
      if (!mounted) return;
      setState(() {
        _items = r.items;
        _total = r.totalMb;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _delete(String name) async {
    try {
      await _api.deleteLora(name);
    } catch (_) {}
    await _load();
  }

  Future<void> _clear() async {
    try {
      await _api.clearLoras();
    } catch (_) {}
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('LoRA 관리')),
          Text('${_total.toStringAsFixed(1)} MB',
              style: const TextStyle(fontSize: 13, color: Colors.white60)),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
            : _err != null
                ? Text('불러오기 실패: $_err')
                : _items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('받아둔 LoRA가 없습니다.'))
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _items.length,
                          separatorBuilder: (_, i) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final l = _items[i];
                            return ListTile(
                              dense: true,
                              title: Text(l.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text('${l.sizeMb.toStringAsFixed(1)} MB'),
                              trailing: IconButton(
                                tooltip: '삭제',
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent),
                                onPressed: () => _delete(l.name),
                              ),
                            );
                          },
                        ),
                      ),
      ),
      actions: [
        if (_items.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep_outlined,
                size: 18, color: Colors.redAccent),
            label: const Text('전체 삭제',
                style: TextStyle(color: Colors.redAccent)),
            onPressed: _clear,
          ),
        IconButton(
            tooltip: '새로고침',
            onPressed: _load,
            icon: const Icon(Icons.refresh)),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기')),
      ],
    );
  }
}
