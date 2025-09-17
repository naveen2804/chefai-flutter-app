import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class CookNowScreen extends StatefulWidget {
  final String recipeMarkdown;
  const CookNowScreen({super.key, required this.recipeMarkdown});

  @override
  State<CookNowScreen> createState() => _CookNowScreenState();
}

class _CookNowScreenState extends State<CookNowScreen> {
  late PageController _pageController;
  late List<String> _instructions;
  int _currentPage = 0;

  // --- NEW TIMER STATE VARIABLES ---
  Timer? _timer;
  Duration _remainingTime = Duration.zero;
  bool get _isTimerRunning => _timer?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _instructions = _extractInstructions(widget.recipeMarkdown);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _timer?.cancel(); // Important: cancel the timer to prevent memory leaks
    super.dispose();
  }

  List<String> _extractInstructions(String markdown) {
    final lines = markdown.split('\n');
    bool inInstructions = false;
    List<String> instructionsList = [];
    for (var line in lines) {
      if (line.contains("## **Instructions**")) {
        inInstructions = true;
        continue;
      }
      if (inInstructions && RegExp(r'^\d+\.').hasMatch(line.trim())) {
        instructionsList.add(line.trim());
      }
    }
    return instructionsList.isEmpty
        ? ["No instructions found."]
        : instructionsList;
  }

  // --- NEW TIMER METHODS ---
  void _startTimer(int minutes) {
    if (minutes <= 0) return;
    setState(() {
      _remainingTime = Duration(minutes: minutes);
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTime.inSeconds <= 0) {
        timer.cancel();
        _onTimerFinish();
      } else {
        if (mounted) {
          setState(() {
            _remainingTime = _remainingTime - const Duration(seconds: 1);
          });
        }
      }
    });
  }

  void _onTimerFinish() async {
    // Play the notification sound
    await FlutterRingtonePlayer().play(
      android: AndroidSounds.notification,
      ios: IosSounds.glass,
      looping: false,
      volume: 1.0,
      asAlarm: false,
    );

    // Show an alert dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Timer Finished!"),
        content: const Text("Your timer is done."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showSetTimerDialog() {
    final minutesController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Set a Timer"),
          content: TextField(
            controller: minutesController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Minutes",
              hintText: "e.g., 10",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final minutes = int.tryParse(minutesController.text);
                if (minutes != null) {
                  _startTimer(minutes);
                  Navigator.of(context).pop();
                }
              },
              child: const Text("Start"),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Step ${_currentPage + 1} of ${_instructions.length}",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  // --- NEW: TIMER DISPLAY ---
                  if (_isTimerRunning)
                    Chip(
                      avatar: const Icon(Icons.timer_outlined),
                      label: Text(
                        _formatDuration(_remainingTime),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _instructions.length,
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                itemBuilder: (context, index) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Text(
                        _instructions[index],
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  // --- NEW: SET TIMER BUTTON ---
                  IconButton(
                    icon: const Icon(Icons.timer_outlined),
                    onPressed: _isTimerRunning ? null : _showSetTimerDialog,
                    tooltip: "Set Timer",
                    iconSize: 28,
                  ),
                  const SizedBox(width: 16),
                  if (_currentPage > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.ease);
                        },
                        child: const Text("Previous"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  if (_currentPage > 0 &&
                      _currentPage < _instructions.length - 1)
                    const SizedBox(width: 16),
                  if (_currentPage < _instructions.length - 1)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.ease);
                        },
                        child: const Text("Next"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  if (_currentPage == _instructions.length - 1)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("Finish Cooking"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
