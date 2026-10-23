import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/exam_provider.dart';
import 'exam_launch_loader.dart';

enum NewDiscussionMode { uploadDocument, aiTopic }

class NewDiscussionModal extends StatefulWidget {
  final bool autoPickFile;
  final NewDiscussionMode initialMode;

  const NewDiscussionModal({
    super.key,
    this.autoPickFile = false,
    this.initialMode = NewDiscussionMode.uploadDocument,
  });

  static Future<void> show(
    BuildContext context, {
    bool autoPickFile = false,
    NewDiscussionMode initialMode = NewDiscussionMode.uploadDocument,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewDiscussionModal(
        autoPickFile: autoPickFile,
        initialMode: initialMode,
      ),
    );
  }

  @override
  State<NewDiscussionModal> createState() => _NewDiscussionModalState();
}

class _NewDiscussionModalState extends State<NewDiscussionModal> {
  AppColors get colors => context.colors;
  // Mode selection: DEFAULT IS uploadDocument as requested
  late NewDiscussionMode _currentMode;

  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final _topicController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
  }

  String? _selectedFileName;
  Uint8List? _selectedFileBytes;
  int? _selectedFileSize;
  bool _isUploading = false;
  String? _errorMessage;

  final List<String> _suggestedAiTopics = [
    'Diritto Costituzionale: Il Parlamento',
    'Fisica Generale I: Meccanica e Dinamica',
    'Sistemi Operativi: Concorrenza e Deadlock',
    'Machine Learning e Reti Neurali',
    'Economia Politica: Microeconomia',
    'Letteratura Italiana del Novecento',
  ];

  final List<Map<String, String>> _sampleTopics = [
    {
      'title': 'Diritto Costituzionale',
      'notes': '# Principi Fondamentali della Costituzione\nLa sovranita appartiene al popolo.\n\n## Corte Costituzionale\nComposizione e compiti di controllo di legittimita costituzionale.',
    },
    {
      'title': 'Fisica Generale I',
      'notes': '# Meccanica del Punto Materiale\nLeggi della dinamica di Newton.\n\n## Conservazione dell Energia\nLavoro ed energia potenziale in campi conservativi.',
    },
    {
      'title': 'Sistemi Operativi',
      'notes': '# Gestione della Memoria\nPaginazione e segmentazione virtuale.\n\n## Concorrenza e Deadlock\nCondizioni di Coffman e algoritmi di sincronizzazione.',
    },
    {
      'title': 'Letteratura Contemporanea',
      'notes': '# Il Novecento Italiano\nEvoluzione poetica tra ermetismo e neorealismo.\n\n## Italo Calvino\nDal sentiero dei nidi di ragno alle lezioni americane.',
    },
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() => _errorMessage = null);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md', 'doc', 'docx'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();

        setState(() {
          _selectedFileName = file.name;
          _selectedFileBytes = bytes;
          _selectedFileSize = bytes.length;
          if (_titleController.text.trim().isEmpty) {
            final cleanName = file.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '').replaceAll('_', ' ');
            _titleController.text = cleanName[0].toUpperCase() + cleanName.substring(1);
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Impossibile selezionare il file: $e');
    }
  }

  void _clearSelectedFile() {
    setState(() {
      _selectedFileName = null;
      _selectedFileBytes = null;
      _selectedFileSize = null;
    });
  }

  void _selectSampleTopic(Map<String, String> topic) {
    setState(() {
      _selectedFileName = null;
      _selectedFileBytes = null;
      _selectedFileSize = null;
      _titleController.text = topic['title']!;
      _notesController.text = topic['notes']!;
      _errorMessage = null;
    });
  }

  void _selectAiTopic(String topic) {
    setState(() {
      _topicController.text = topic;
      if (_titleController.text.trim().isEmpty) {
        _titleController.text = topic.split(':').first.trim();
      }
      _errorMessage = null;
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _submitAndStartExam() async {
    final exam = context.read<ExamProvider>();

    if (_currentMode == NewDiscussionMode.uploadDocument) {
      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : (_selectedFileName ?? 'Nuova Discussione d\'Esame');

      final text = _notesController.text.trim();

      if (_selectedFileBytes == null && text.isEmpty) {
        setState(() {
          _errorMessage = 'Seleziona un file (PDF, TXT) o inserisci degli appunti di studio.';
        });
        return;
      }

      setState(() {
        _isUploading = true;
        _errorMessage = null;
      });

      try {
        await exam.uploadDocumentAndStartNewDiscussion(
          title: title,
          text: text.isNotEmpty ? text : null,
          filename: _selectedFileName ?? 'appunti_esame.md',
          fileBytes: _selectedFileBytes,
        );

        if (mounted) {
          final nav = Navigator.of(context);
          nav.pop();
          await launchExamWithLoader(
            nav.context,
            onConnect: () async {
              await exam.fetchStatus();
            },
            initialSubtitle: 'Caricamento informazioni e messaggi...',
            completedSubtitle: 'Documento pronto! Si comincia 😉',
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isUploading = false;
            _errorMessage = e.toString().replaceAll('Exception: ', '');
          });
        }
      }
    } else {
      // AI Topic mode
      final topic = _topicController.text.trim();
      if (topic.isEmpty) {
        setState(() {
          _errorMessage = 'Inserisci l\'argomento o la materia d\'esame da far generare all\'IA.';
        });
        return;
      }

      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : topic.split(':').first.trim();

      setState(() {
        _isUploading = true;
        _errorMessage = null;
      });

      try {
        await exam.generateExamFromTopicAndStartNewDiscussion(
          topic: topic,
          title: title.isNotEmpty ? title : null,
        );

        if (mounted) {
          final nav = Navigator.of(context);
          nav.pop();
          await launchExamWithLoader(
            nav.context,
            onConnect: () async {
              await exam.fetchStatus();
            },
            initialSubtitle: 'Generazione programma e messaggi...',
            completedSubtitle: 'Materia generata! Si comincia 😉',
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isUploading = false;
            _errorMessage = e.toString().replaceAll('Exception: ', '');
          });
        }
      }
    }
  }

  Widget _buildModeTab({
    required NewDiscussionMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
    bool isRecommended = false,
  }) {
    final isSelected = _currentMode == mode;
    return InkWell(
      onTap: _isUploading
          ? null
          : () {
              setState(() {
                _currentMode = mode;
                _errorMessage = null;
              });
            },
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primaryContainer.withValues(alpha: 0.16)
              : colors.surfaceContainerHigh.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: isSelected ? colors.primaryContainer : colors.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.primaryContainer.withValues(alpha: 0.22)
                    : colors.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? colors.primaryContainer : colors.textSecondary,
                size: 18,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: isSelected ? colors.primaryContainer : colors.textPrimary,
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'DEFAULT',
                            style: TextStyle(
                              color: colors.primaryContainer,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isSelected ? colors.textSecondary : colors.textTertiary,
                      fontSize: 10.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusHero)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 32,
            offset: Offset(0, -8),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: bottomInset > 0 ? bottomInset + 16 : 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: colors.outlineVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.school_rounded,
                  color: colors.primaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nuova Discussione Orale',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Scegli se caricare un documento o generare dall\'IA',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: colors.textSecondary),
                onPressed: _isUploading ? null : () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Mode Selection Bar: Choice 1 (Default) vs Choice 2
          Row(
            children: [
              Expanded(
                child: _buildModeTab(
                  mode: NewDiscussionMode.uploadDocument,
                  icon: Icons.upload_file_rounded,
                  title: 'Carica Documento',
                  subtitle: 'PDF, Slide, Appunti',
                  isRecommended: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeTab(
                  mode: NewDiscussionMode.aiTopic,
                  icon: Icons.auto_awesome_rounded,
                  title: 'Genera con IA',
                  subtitle: 'Da un Argomento',
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Content scroll area
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Error Banner if any
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: colors.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: colors.error, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // MODE 1: UPLOAD DOCUMENT (DEFAULT)
                  if (_currentMode == NewDiscussionMode.uploadDocument) ...[
                    Text(
                      'Carica Documento di Studio (PDF, Slide o TXT)',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (_selectedFileName == null)
                      InkWell(
                        onTap: _isUploading ? null : _pickFile,
                        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                            border: Border.all(
                              color: colors.outlineVariant,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colors.primaryContainer.withValues(alpha: 0.15),
                                ),
                                child: Icon(
                                  Icons.upload_file_rounded,
                                  color: colors.primaryContainer,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Tocca per selezionare PDF o dispense',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Supporta .pdf, .txt, .md, .docx • L\'IA estrarrà il piano d\'esame',
                                style: TextStyle(
                                  color: colors.textTertiary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                          border: Border.all(color: colors.primaryContainer.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.description_rounded, color: colors.primaryContainer, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedFileName!,
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (_selectedFileSize != null)
                                    Text(
                                      _formatFileSize(_selectedFileSize!),
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.cancel_rounded, color: colors.textSecondary, size: 20),
                              onPressed: _isUploading ? null : _clearSelectedFile,
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    Text(
                      'Materia o Titolo Corso (Facoltativo)',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleController,
                      enabled: !_isUploading,
                      style: TextStyle(color: colors.textPrimary, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'es. Diritto Pubblico, Reti di Calcolatori, Anatomia...',
                        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12.5),
                        filled: true,
                        fillColor: colors.surfaceContainerHigh,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(Icons.school_rounded, color: colors.textSecondary, size: 18),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'Oppure Incolla Appunti / Sintesi',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      enabled: !_isUploading,
                      maxLines: 3,
                      style: TextStyle(color: colors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Incolla qui testi, dispense o capitoli chiave...',
                        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12),
                        filled: true,
                        fillColor: colors.surfaceContainerHigh,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text(
                      'Oppure scegli una materia di esempio',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sampleTopics.map((item) {
                        final isSelected = _titleController.text == item['title'];
                        return ChoiceChip(
                          label: Text(
                            item['title']!,
                            style: TextStyle(
                              color: isSelected ? colors.onPrimary : colors.textPrimary,
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: colors.primaryContainer,
                          backgroundColor: colors.surfaceContainerHigh,
                          side: BorderSide(
                            color: isSelected ? colors.primaryContainer : colors.outlineVariant,
                          ),
                          onSelected: _isUploading ? null : (_) => _selectSampleTopic(item),
                        );
                      }).toList(),
                    ),
                  ] else ...[
                    // MODE 2: GENERATE PURELY FROM TOPIC WITH AI
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                        border: Border.all(color: colors.primaryContainer.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.auto_awesome_rounded, color: colors.primaryContainer, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Nessun file necessario: l\'IA strutturerà un intero esame accademico (concetti, domande e risposte ideali) direttamente sull\'argomento indicato.',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'Argomento o Tema d\'Esame',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _topicController,
                      enabled: !_isUploading,
                      maxLines: 2,
                      style: TextStyle(color: colors.textPrimary, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'es. Meccanica Quantistica, Diritto Penale: Reati contro il Patrimonio, Reti Neurali...',
                        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12.5),
                        filled: true,
                        fillColor: colors.surfaceContainerHigh,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(Icons.psychology_rounded, color: colors.primaryContainer, size: 20),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'Materia / Titolo Corso (Facoltativo)',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleController,
                      enabled: !_isUploading,
                      style: TextStyle(color: colors.textPrimary, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'es. Diritto Penale I, Fisica Moderna...',
                        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12.5),
                        filled: true,
                        fillColor: colors.surfaceContainerHigh,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(Icons.school_rounded, color: colors.textSecondary, size: 18),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'Suggerimenti di Argomenti Rapidi',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _suggestedAiTopics.map((topic) {
                        final isSelected = _topicController.text == topic;
                        return ActionChip(
                          avatar: Icon(
                            Icons.bolt_rounded,
                            size: 15,
                            color: isSelected ? colors.onPrimary : colors.primaryContainer,
                          ),
                          label: Text(
                            topic,
                            style: TextStyle(
                              color: isSelected ? colors.onPrimary : colors.textPrimary,
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          backgroundColor: isSelected ? colors.primaryContainer : colors.surfaceContainerHigh,
                          side: BorderSide(
                            color: isSelected ? colors.primaryContainer : colors.outlineVariant,
                          ),
                          onPressed: _isUploading ? null : () => _selectAiTopic(topic),
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Submit CTA Button
          Container(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _submitAndStartExam,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                  ),
                  elevation: 6,
                  shadowColor: colors.primaryContainer.withValues(alpha: 0.4),
                ),
                child: _isUploading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: colors.onPrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _currentMode == NewDiscussionMode.uploadDocument
                                ? 'Analisi Documento & Avvio Orale...'
                                : 'Generazione IA & Avvio Orale...',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _currentMode == NewDiscussionMode.uploadDocument
                                ? Icons.file_upload_rounded
                                : Icons.auto_awesome_rounded,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _currentMode == NewDiscussionMode.uploadDocument
                                ? 'Carica Documento & Inizia Orale'
                                : 'Genera Esame con IA & Inizia',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
