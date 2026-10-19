import 'dart:async';
import 'package:flutter/material.dart';
import 'services/api.dart';

class RemoteOption extends StatefulWidget {
  final Api api;
  final String path, title;
  final String? value;
  final bool optional;
  final void Function(Map<String, dynamic>?) onSelected;
  const RemoteOption(
      {super.key,
      required this.api,
      required this.path,
      required this.title,
      this.value,
      this.optional = false,
      required this.onSelected});
  @override
  State<RemoteOption> createState() => _RemoteOptionState();
}

class _RemoteOptionState extends State<RemoteOption> {
  String? selectedLabel;
  @override
  void initState() {
    super.initState();
    resolve();
  }

  @override
  void didUpdateWidget(RemoteOption old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value || old.path != widget.path) resolve();
  }

  Future<void> resolve() async {
    final value = widget.value;
    if (value == null || value.isEmpty) {
      if (mounted) setState(() => selectedLabel = null);
      return;
    }
    try {
      final separator = widget.path.contains('?') ? '&' : '?';
      final result = await widget.api.call(
              '${widget.path}${separator}selected=${Uri.encodeComponent(value)}')
          as List;
      if (mounted && widget.value == value) {
        setState(() => selectedLabel =
            result.isEmpty ? 'Choose again' : result.first['label']);
      }
    } catch (_) {
      if (mounted) setState(() => selectedLabel = 'Retry selection');
    }
  }

  @override
  Widget build(BuildContext context) => FormField<String>(
      validator: (_) =>
          !widget.optional && (widget.value == null || widget.value!.isEmpty)
              ? 'Choose ${widget.title.toLowerCase()}'
              : null,
      builder: (state) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title),
            OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: Text(selectedLabel ?? 'Search and select'),
                onPressed: () async {
                  final result = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (_) => OptionDialog(
                          api: widget.api,
                          path: widget.path,
                          title: widget.title));
                  if (result != null) {
                    widget.onSelected(result);
                    state.didChange(result['value']);
                  }
                }),
            if (widget.optional && widget.value?.isNotEmpty == true)
              TextButton(
                  onPressed: () {
                    widget.onSelected(null);
                    state.didChange(null);
                  },
                  child: const Text('Clear selection')),
            if (state.hasError)
              Text(state.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))
          ]));
}

class OptionDialog extends StatefulWidget {
  final Api api;
  final String path, title;
  const OptionDialog(
      {super.key, required this.api, required this.path, required this.title});
  @override
  State<OptionDialog> createState() => _OptionDialogState();
}

class _OptionDialogState extends State<OptionDialog> {
  List<dynamic> options = [];
  String? error;
  bool loading = true;
  Timer? timer;
  int sequence = 0;
  @override
  void initState() {
    super.initState();
    search('');
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> search(String query) async {
    final request = ++sequence;
    setState(() => loading = true);
    try {
      final separator = widget.path.contains('?') ? '&' : '?';
      final result = await widget.api
          .call('${widget.path}${separator}q=${Uri.encodeComponent(query)}');
      if (mounted && request == sequence) {
        setState(() {
          options = result;
          error = null;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && request == sequence) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
              width: 500,
              height: 400,
              child: Column(children: [
                TextField(
                    autofocus: true,
                    maxLength: 100,
                    decoration: const InputDecoration(
                        labelText: 'Search', prefixIcon: Icon(Icons.search)),
                    onChanged: (q) {
                      timer?.cancel();
                      timer = Timer(
                          const Duration(milliseconds: 300), () => search(q));
                    }),
                if (loading) const LinearProgressIndicator(),
                if (error != null) Text(error!),
                Expanded(
                    child: ListView(children: [
                  for (final option in options)
                    ListTile(
                        title: Text(option['label']),
                        onTap: () => Navigator.pop(
                            context, Map<String, dynamic>.from(option)))
                ])),
                const Text(
                    'Showing up to 30 matches. Type to narrow the results.',
                    style: TextStyle(fontSize: 12))
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'))
          ]);
}
