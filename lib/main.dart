import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const SudokuApp());
}

class SudokuApp extends StatefulWidget {
  const SudokuApp({super.key});

  @override
  State<SudokuApp> createState() => _SudokuAppState();
}

class _SudokuAppState extends State<SudokuApp> with TickerProviderStateMixin {
  bool _isDarkMode = false;
  late AnimationController _themeAnimationController;
  late Animation<double> _themeAnimation;

  @override
  void initState() {
    super.initState();
    _themeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _themeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _themeAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _themeAnimationController.dispose();
    super.dispose();
  }

  void _toggleTheme() {
    if (_isDarkMode) {
      _themeAnimationController.reverse().then((_) {
        setState(() {
          _isDarkMode = !_isDarkMode;
        });
      });
    } else {
      setState(() {
        _isDarkMode = !_isDarkMode;
      });
      _themeAnimationController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sudoku',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: Stack(
        children: [
          SudokuHomePage(onToggleTheme: _toggleTheme, isDarkMode: _isDarkMode),
          AnimatedBuilder(
            animation: _themeAnimation,
            builder: (context, child) {
              return IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(_themeAnimation.value * 0.3),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class SudokuHomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  const SudokuHomePage({
    super.key,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  @override
  State<SudokuHomePage> createState() => _SudokuHomePageState();
}

class _SudokuHomePageState extends State<SudokuHomePage> {
  // Sudoku grid: 9x9, 0 means empty
  late List<List<int>> _grid;
  late List<List<int>> _initialGrid;
  late List<List<bool>> _editable;
  late List<List<List<int>>> _history;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGame();
  }

  Future<void> _loadGame() async {
    final prefs = await SharedPreferences.getInstance();
    final gridString = prefs.getString('sudoku_grid');
    final initialGridString = prefs.getString('sudoku_initial_grid');
    final editableString = prefs.getString('sudoku_editable');
    final historyString = prefs.getString('sudoku_history');

    if (gridString != null && initialGridString != null && editableString != null && historyString != null) {
      setState(() {
        _grid = List<List<int>>.from(jsonDecode(gridString).map((x) => List<int>.from(x)));
        _initialGrid = List<List<int>>.from(jsonDecode(initialGridString).map((x) => List<int>.from(x)));
        _editable = List<List<bool>>.from(jsonDecode(editableString).map((x) => List<bool>.from(x)));
        _history = List<List<List<int>>>.from(jsonDecode(historyString).map((x) => List<List<int>>.from(x.map((y) => List<int>.from(y)))));
        _isLoading = false;
      });
    } else {
      _initialGrid = _generatePuzzle();
      _grid = List.generate(9, (i) => List.from(_initialGrid[i]));
      _editable = List.generate(
        9,
        (i) => List.generate(9, (j) => _initialGrid[i][j] == 0),
      );
      _history = [];
      setState(() {
        _isLoading = false;
      });
      _saveGame();
    }
  }

  Future<void> _saveGame() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sudoku_grid', jsonEncode(_grid));
    await prefs.setString('sudoku_initial_grid', jsonEncode(_initialGrid));
    await prefs.setString('sudoku_editable', jsonEncode(_editable));
    await prefs.setString('sudoku_history', jsonEncode(_history));
  }

  void _newGame() {
    setState(() {
      _initialGrid = _generatePuzzle();
      _grid = List.generate(9, (i) => List.from(_initialGrid[i]));
      _editable = List.generate(
        9,
        (i) => List.generate(9, (j) => _initialGrid[i][j] == 0),
      );
      _history = [];
    });
  }

  void _restart() {
    setState(() {
      _grid = List.generate(9, (i) => List.from(_initialGrid[i]));
      _editable = List.generate(
        9,
        (i) => List.generate(9, (j) => _initialGrid[i][j] == 0),
      );
      _history = [];
    });
    _saveGame();
  }

  void _undo() {
    if (_history.isNotEmpty) {
      setState(() {
        _grid = _history.removeLast();
      });
      _saveGame();
    }
  }

  void _onCellChanged(int row, int col, String value) {
    if (!_editable[row][col]) return;
    int? num = int.tryParse(value);
    if (num == null || num < 1 || num > 9) return;
    setState(() {
      _history.add(List.generate(9, (i) => List.from(_grid[i])));
      _grid[row][col] = num;
      // Check if grid is full
      int emptyCount = 0;
      for (var r in _grid) {
        for (var cell in r) {
          if (cell == 0) emptyCount++;
        }
      }
      if (emptyCount == 0) {
        if (_isGridValid()) {
          // Freeze all cells if valid
          for (int i = 0; i < 9; i++) {
            for (int j = 0; j < 9; j++) {
              _editable[i][j] = false;
            }
          }
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Parabéns! Você resolveu o Sudoku!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Grid completo, mas há conflitos. Revise sua solução!',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    });
    _saveGame();
  }

  bool _isComplete(List<int> list) {
    Set<int> set = {};
    for (int num in list) {
      if (num == 0 || set.contains(num)) return false;
      set.add(num);
    }
    return set.length == 9;
  }

  bool _isGridValid() {
    // Check rows
    for (int i = 0; i < 9; i++) {
      if (!_isComplete(_grid[i])) return false;
    }
    // Check columns
    for (int j = 0; j < 9; j++) {
      List<int> col = List.generate(9, (i) => _grid[i][j]);
      if (!_isComplete(col)) return false;
    }
    // Check boxes
    for (int bi = 0; bi < 3; bi++) {
      for (int bj = 0; bj < 3; bj++) {
        List<int> box = [];
        for (int i = bi * 3; i < (bi + 1) * 3; i++) {
          for (int j = bj * 3; j < (bj + 1) * 3; j++) {
            box.add(_grid[i][j]);
          }
        }
        if (!_isComplete(box)) return false;
      }
    }
    return true;
  }

  List<List<int>> _generatePuzzle() {
    // Start with empty grid
    List<List<int>> tempGrid = List.generate(9, (_) => List.filled(9, 0));
    // Solve to get a full grid
    _solveGrid(tempGrid);
    List<List<int>> fullGrid = List.generate(9, (i) => List.from(tempGrid[i]));
    // Remove some numbers to create puzzle
    List<int> positions = List.generate(81, (i) => i)..shuffle();
    int toRemove = 45; // Remove about 45 cells
    for (int k = 0; k < toRemove; k++) {
      int pos = positions[k];
      int i = pos ~/ 9;
      int j = pos % 9;
      fullGrid[i][j] = 0;
    }
    return fullGrid;
  }

  bool _solveGrid(List<List<int>> grid) {
    for (int i = 0; i < 9; i++) {
      for (int j = 0; j < 9; j++) {
        if (grid[i][j] == 0) {
          List<int> nums = List.generate(9, (k) => k + 1)..shuffle();
          for (int num in nums) {
            if (_isValidGrid(grid, i, j, num)) {
              grid[i][j] = num;
              if (_solveGrid(grid)) return true;
              grid[i][j] = 0;
            }
          }
          return false;
        }
      }
    }
    return true;
  }

  bool _isValidGrid(List<List<int>> grid, int row, int col, int num) {
    // Check row
    for (int j = 0; j < 9; j++) {
      if (grid[row][j] == num) return false;
    }
    // Check column
    for (int i = 0; i < 9; i++) {
      if (grid[i][col] == num) return false;
    }
    // Check box
    int bi = row ~/ 3;
    int bj = col ~/ 3;
    for (int i = bi * 3; i < (bi + 1) * 3; i++) {
      for (int j = bj * 3; j < (bj + 1) * 3; j++) {
        if (grid[i][j] == num) return false;
      }
    }
    return true;
  }

  Widget _buildStyledButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required bool isDarkMode,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: (isDarkMode ? Colors.black : Colors.grey).withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          label: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            backgroundColor: isDarkMode
                ? Colors.purple.shade700
                : Colors.purple.shade600,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Sudoku'),
          actions: [
            IconButton(
              icon: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: widget.onToggleTheme,
            ),
          ],
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sudoku'),
        actions: [
          IconButton(
            icon: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 9,
                  ),
                  itemCount: 81,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, index) {
                    int row = index ~/ 9;
                    int col = index % 9;
                    Color borderColor = widget.isDarkMode
                        ? Colors.white70
                        : Colors.black;
                    Color cellColor = _editable[row][col]
                        ? (widget.isDarkMode ? Colors.grey[800]! : Colors.white)
                        : (widget.isDarkMode
                              ? Colors.grey[700]!
                              : Colors.grey[300]!);
                    Color textColor = widget.isDarkMode
                        ? Colors.white
                        : Colors.black;
                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: borderColor,
                            width: row == 0 ? 3 : 1,
                          ),
                          bottom: BorderSide(
                            color: borderColor,
                            width: row == 8 ? 3 : (row % 3 == 2 ? 3 : 1),
                          ),
                          left: BorderSide(
                            color: borderColor,
                            width: col == 0 ? 3 : 1,
                          ),
                          right: BorderSide(
                            color: borderColor,
                            width: col == 8 ? 3 : (col % 3 == 2 ? 3 : 1),
                          ),
                        ),
                        color: cellColor,
                      ),
                      child: Center(
                        child: TextField(
                          controller: TextEditingController(
                            text: _grid[row][col] == 0
                                ? ''
                                : _grid[row][col].toString(),
                          ),
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[1-9]')),
                          ],
                          enabled: _editable[row][col],
                          onChanged: (value) => _onCellChanged(row, col, value),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            counterText: '',
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStyledButton(
                label: 'Novo jogo',
                icon: Icons.add,
                onPressed: _newGame,
                isDarkMode: widget.isDarkMode,
              ),
              _buildStyledButton(
                label: 'Reiniciar',
                icon: Icons.restart_alt,
                onPressed: _restart,
                isDarkMode: widget.isDarkMode,
              ),
              _buildStyledButton(
                label: 'Desfazer',
                icon: Icons.undo,
                onPressed: _undo,
                isDarkMode: widget.isDarkMode,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
