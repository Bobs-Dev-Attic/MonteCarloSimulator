import 'package:flutter/material.dart';

/// Three-tab layout (Fan chart / Histogram / Summary) for the results
/// screen. Tab bodies are provided by the caller so the parent can
/// vary content based on comparison mode without this widget knowing.
class ResultsTabs extends StatelessWidget {
  const ResultsTabs({
    super.key,
    required this.fanTab,
    required this.histogramTab,
    required this.summaryTab,
  });

  final Widget fanTab;
  final Widget histogramTab;
  final Widget summaryTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Fan chart'),
              Tab(text: 'Histogram'),
              Tab(text: 'Summary'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [fanTab, histogramTab, summaryTab],
            ),
          ),
        ],
      ),
    );
  }
}
