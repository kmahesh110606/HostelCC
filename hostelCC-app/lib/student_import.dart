import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import 'services/api.dart';

class StudentImportScreen extends StatefulWidget {
  final Api api;
  const StudentImportScreen({super.key, required this.api});
  @override
  State<StudentImportScreen> createState() => _StudentImportScreenState();
}

class _StudentImportScreenState extends State<StudentImportScreen> {
  String csv = '', name = '';
  String? error;
  Map<String, dynamic>? report;
  bool busy = false;
  Future<void> pick() async {
    try {
      final file = await openFile(acceptedTypeGroups: [
        const XTypeGroup(
            label: 'CSV',
            extensions: ['csv'],
            mimeTypes: ['text/csv', 'text/plain'],
            uniformTypeIdentifiers: ['public.comma-separated-values-text'])
      ]);
      if (file == null) return;
      if (await file.length() > 500000) {
        throw Exception('Use a file smaller than 500 KB.');
      }
      final text = await file.readAsString();
      if (mounted) {
        setState(() {
          csv = text;
          name = file.name;
          report = null;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> submit(bool commit) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.call(
          '/admin/students/import${commit ? '' : '/validate'}',
          method: 'POST',
          body: {'csv': csv});
      if (mounted) {
        if (commit) {
          Navigator.pop(context, true);
        } else {
          setState(() => report = Map.from(result));
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Import students')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text(
            'Add blocks, rooms and messes first. Import up to 1,000 students per CSV. Existing accounts are never overwritten.'),
        TextButton(
            onPressed: () async {
              try {
                await Share.shareXFiles([
                  XFile.fromData(
                      utf8.encode(
                          'name,email,rollNo,block,room,mess,phone,cloakroomAccess\nExample Student,student@example.edu,STUDENT001,North House,101,Main Mess,,false,false\n'),
                      mimeType: 'text/csv',
                      name: 'students-template.csv')
                ]);
              } catch (e) {
                if (mounted) setState(() => error = e.toString());
              }
            },
            child: const Text('Save CSV template')),
        OutlinedButton(
            onPressed: busy ? null : pick,
            child: const Text('Choose CSV file')),
        if (name.isNotEmpty) Text(name),
        if (csv.isNotEmpty)
          FilledButton(
              onPressed: busy ? null : () => submit(false),
              child: const Text('Validate file')),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (report != null) ...[
          Text(
              '${report!['count']} valid students · ${(report!['errors'] as List).length} errors'),
          for (final row in report!['errors'])
            Text('Row ${row['row']}: ${row['message']}'),
          for (final row in report!['preview'])
            ListTile(
                title: Text(row['name']),
                subtitle: Text('${row['rollNo']} · ${row['email']}')),
          if (report!['valid'] == true)
            FilledButton(
                onPressed: busy ? null : () => submit(true),
                child: Text('Import ${report!['count']} students'))
        ]
      ]));
}
