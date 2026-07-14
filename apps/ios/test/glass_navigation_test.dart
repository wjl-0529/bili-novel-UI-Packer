import 'package:bili_novel_packer_ios/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('glass slider follows and stretches with page progress', (
    tester,
  ) async {
    final pageController = PageController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageView(
            controller: pageController,
            children: const [SizedBox(), SizedBox(), SizedBox()],
          ),
          bottomNavigationBar: SafeArea(
            child: GlassBottomNavigationBar(
              selectedIndex: 0,
              pageController: pageController,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    final slider = find.byKey(const Key('glass-navigation-slider'));
    final track = find.byKey(const Key('glass-navigation-track'));
    final startLeft = tester.getTopLeft(slider).dx;
    final startWidth = tester.getSize(slider).width;
    final itemWidth = tester.getSize(track).width / 3;

    pageController.jumpTo(pageController.position.viewportDimension * 0.5);
    await tester.pump();

    expect(tester.getTopLeft(slider).dx, greaterThan(startLeft));
    expect(tester.getSize(slider).width, greaterThan(startWidth));

    pageController.jumpTo(pageController.position.viewportDimension);
    await tester.pump();

    expect(tester.getTopLeft(slider).dx, closeTo(startLeft + itemWidth, 1));
    expect(tester.getSize(slider).width, closeTo(startWidth, 0.1));

    await tester.pumpWidget(const SizedBox());
    pageController.dispose();
  });
}
