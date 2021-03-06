library dirty_chekcing_change_detector_spec;

import 'package:guinness/guinness.dart';
import 'package:unittest/unittest.dart' show Matcher, Description;
import '../lib/change_detection.dart';
import '../lib/dirty_checking_change_detector.dart';
import '../lib/dirty_checking_change_detector_static.dart';
import '../lib/dirty_checking_change_detector_dynamic.dart';
import 'dart:collection';
import 'dart:math';

void testWithGetterFactory(FieldGetterFactory getterFactory) {
  describe('DirtyCheckingChangeDetector with ${getterFactory.runtimeType}', () {
    DirtyCheckingChangeDetector<String> detector;

    beforeEach(() {
      detector = new DirtyCheckingChangeDetector<String>(getterFactory);
    });

    describe('object field', () {
      it('should detect nothing', () {
        var changes = detector.collectChanges();
        expect(changes.moveNext()).toEqual(false);
      });

      it('should detect field changes', () {
        var user = new _User('', '');
        Iterator changeIterator;

        detector.watch(user, 'first', null);
        detector.watch(user, 'last', null);
        detector.collectChanges(); // throw away first set

        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(false);
        user.first = 'misko';
        user.last = 'hevery';

        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue).toEqual('misko');
        expect(changeIterator.current.previousValue).toEqual('');
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue).toEqual('hevery');
        expect(changeIterator.current.previousValue).toEqual('');
        expect(changeIterator.moveNext()).toEqual(false);

        // force different instance
        user.first = 'mis';
        user.first += 'ko';

        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(false);

        user.last = 'Hevery';
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue).toEqual('Hevery');
        expect(changeIterator.current.previousValue).toEqual('hevery');
        expect(changeIterator.moveNext()).toEqual(false);
      });

      it('should ignore NaN != NaN', () {
        var user = new _User();
        user.age = double.NAN;
        detector.watch(user, 'age', null); 
        detector.collectChanges(); // throw away first set

        var changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(false);

        user.age = 123;
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue).toEqual(123);
        expect(changeIterator.current.previousValue.isNaN).toEqual(true);
        expect(changeIterator.moveNext()).toEqual(false);
      });

      it('should treat map field dereference as []', () {
        var obj = {'name':'misko'};
        detector.watch(obj, 'name', null);
        detector.collectChanges(); // throw away first set

        obj['name'] = 'Misko';
        var changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue).toEqual('Misko');
        expect(changeIterator.current.previousValue).toEqual('misko');
      });
    });

    describe('insertions / removals', () {
      it('should insert at the end of list', () {
        var obj = {};
        var a = detector.watch(obj, 'a', 'a');
        var b = detector.watch(obj, 'b', 'b');

        obj['a'] = obj['b'] = 1;
        var changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.handler).toEqual('a');
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.handler).toEqual('b');
        expect(changeIterator.moveNext()).toEqual(false);

        obj['a'] = obj['b'] = 2;
        a.remove();
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.handler).toEqual('b');
        expect(changeIterator.moveNext()).toEqual(false);

        obj['a'] = obj['b'] = 3;
        b.remove();
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(false);
      });

      it('should remove all watches in group and group\'s children', () {
        var obj = {};
        detector.watch(obj, 'a', '0a');
        var child1a = detector.newGroup();
        var child1b = detector.newGroup();
        var child2 = child1a.newGroup();
        child1a.watch(obj,'a', '1a');
        child1b.watch(obj,'a', '1b');
        detector.watch(obj, 'a', '0A');
        child1a.watch(obj,'a', '1A');
        child2.watch(obj,'a', '2A');

        var iterator;
        obj['a'] = 1;
        expect(detector.collectChanges(),
            toEqualChanges(['0a', '0A', '1a', '1A', '2A', '1b']));

        obj['a'] = 2;
        child1a.remove(); // should also remove child2
        expect(detector.collectChanges(), toEqualChanges(['0a', '0A', '1b']));
      });

      it('should add watches within its own group', () {
        var obj = {};
        var ra = detector.watch(obj, 'a', 'a');
        var child = detector.newGroup();
        var cb = child.watch(obj,'b', 'b');
        var iterotar;

        obj['a'] = obj['b'] = 1;
        expect(detector.collectChanges(), toEqualChanges(['a', 'b']));

        obj['a'] = obj['b'] = 2;
        ra.remove();
        expect(detector.collectChanges(), toEqualChanges(['b']));

        obj['a'] = obj['b'] = 3;
        cb.remove();
        expect(detector.collectChanges(), toEqualChanges([]));

        // TODO: add them back in wrong order, assert events in right order
        cb = child.watch(obj,'b', 'b');
        ra = detector.watch(obj, 'a', 'a');
        obj['a'] = obj['b'] = 4;
        expect(detector.collectChanges(), toEqualChanges(['a', 'b']));
      });

      it('should properly add children', () {
        var a = detector.newGroup();
        var aChild = a.newGroup();
        var b = detector.newGroup();
        expect(detector.collectChanges).not.toThrow();
      });

      it('should properly disconnect group in case watch is removed in disconected group', () {
        var map = {};
        var detector0 = new DirtyCheckingChangeDetector<String>(getterFactory);
          var detector1 = detector0.newGroup();
            var detector2 = detector1.newGroup();
            var watch2 = detector2.watch(map, 'f1', null);
          var detector3 = detector0.newGroup();
          detector1.remove();
            watch2.remove(); // removing a dead record
          detector3.watch(map, 'f2', null);
      });

      it('should find random bugs', () {
        List detectors;
        List records;
        List steps;
        var field = 'someField';
        step(text) {
          //print(text);
          steps.add(text);
        }
        Map map = {};
        var random = new Random();
        try {
          for (var i = 0; i < 100000; i++) {
            if (i % 50 == 0) {
              records = [];
              steps = [];
              detectors = [new DirtyCheckingChangeDetector<String>(getterFactory)];
            }
            switch (random.nextInt(4)) {
              case 0: // new child detector
                if (detectors.length > 10) break;
                var index = random.nextInt(detectors.length);
                ChangeDetectorGroup detector = detectors[index];
                step('detectors[$index].newGroup()');
                var child = detector.newGroup();
                detectors.add(child);
                break;
              case 1: // add watch
                var index = random.nextInt(detectors.length);
                ChangeDetectorGroup detector = detectors[index];
                step('detectors[$index].watch(map, field, null)');
                WatchRecord record = detector.watch(map, field, null);
                records.add(record);
                break;
              case 2: // destroy watch group
                if (detectors.length == 1) break;
                var index = random.nextInt(detectors.length - 1) + 1;
                ChangeDetectorGroup detector = detectors[index];
                step('detectors[$index].remove()');
                detector.remove();
                detectors = detectors
                    .where((s) => s.isAttached)
                    .toList();
                break;
              case 3: // remove watch on watch group
                if (records.length == 0) break;
                var index = random.nextInt(records.length);
                WatchRecord record = records.removeAt(index);
                step('records.removeAt($index).remove()');
                record.remove();
                break;
            }
          }
        } catch(e) {
          print(steps);
          rethrow;
        }
      });

    });

    describe('list watching', () {
      describe('previous state', () {
        it('should store on addition', () {
          var list = [];
          var record = detector.watch(list, null, null);
          expect(detector.collectChanges().moveNext()).toEqual(false);
          var iterator;

          list.add('a');
          iterator = detector.collectChanges();
          expect(iterator.moveNext()).toEqual(true);
          expect(iterator.current.currentValue, toEqualCollectionRecord(
              ['a[null -> 0]'],
              [],
              ['a[null -> 0]'],
              [],
              []));

          list.add('b');
          iterator = detector.collectChanges();
          expect(iterator.moveNext()).toEqual(true);
          expect(iterator.current.currentValue, toEqualCollectionRecord(
              ['a', 'b[null -> 1]'],
              ['a'],
              ['b[null -> 1]'],
              [],
              []));
        });

        it('should handle swapping elements correctly', () {
          var list = [1, 2];
          var record = detector.watch(list, null, null);
          detector.collectChanges().moveNext();
          var iterator;

          // reverse the list.
          list.setAll(0, list.reversed.toList());
          iterator = detector.collectChanges();
          expect(iterator.moveNext()).toEqual(true);
          expect(iterator.current.currentValue, toEqualCollectionRecord(
              ['2[1 -> 0]', '1[0 -> 1]'],
              ['1[0 -> 1]', '2[1 -> 0]'],
              [],
              ['2[1 -> 0]', '1[0 -> 1]'],
              []));
        });

        it('should handle swapping elements correctly - gh1097', () {
          // This test would only have failed in non-checked mode only
          var list = ['a', 'b', 'c'];
          var record = detector.watch(list, null, null);
          var iterator = detector.collectChanges();
          iterator.moveNext();

          list.clear(); 
          list.addAll(['b', 'a', 'c']);
          iterator = detector.collectChanges();
          iterator.moveNext();
          expect(iterator.current.currentValue, toEqualCollectionRecord(
              ['b[1 -> 0]', 'a[0 -> 1]', 'c'],
              ['a[0 -> 1]', 'b[1 -> 0]', 'c'],
              [],
              ['b[1 -> 0]', 'a[0 -> 1]'],
              []));

          list.clear();
          list.addAll(['b', 'c', 'a']);
          iterator = detector.collectChanges();
          iterator.moveNext();
          expect(iterator.current.currentValue, toEqualCollectionRecord(
              ['b', 'c[2 -> 1]', 'a[1 -> 2]'],
              ['b', 'a[1 -> 2]', 'c[2 -> 1]'],
              [],
              ['c[2 -> 1]', 'a[1 -> 2]'],
              []));
        });
      });

      it('should detect changes in list', () {
        var list = [];
        var record = detector.watch(list, null, 'handler');
        expect(detector.collectChanges().moveNext()).toEqual(false);
        var iterator;

        list.add('a');
        iterator = detector.collectChanges();
        expect(iterator.moveNext()).toEqual(true);
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['a[null -> 0]'],
            null,
            ['a[null -> 0]'],
            [],
            []));

        list.add('b');
        iterator = detector.collectChanges();
        expect(iterator.moveNext()).toEqual(true);
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['a', 'b[null -> 1]'],
            ['a'],
            ['b[null -> 1]'],
            [],
            []));

        list.add('c');
        list.add('d');
        iterator = detector.collectChanges();
        expect(iterator.moveNext()).toEqual(true);
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['a', 'b', 'c[null -> 2]', 'd[null -> 3]'],
            ['a', 'b'],
            ['c[null -> 2]', 'd[null -> 3]'],
            [],
            []));

        list.remove('c');
        expect(list).toEqual(['a', 'b', 'd']);
        iterator = detector.collectChanges();
        expect(iterator.moveNext()).toEqual(true);
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['a', 'b', 'd[3 -> 2]'],
            ['a', 'b', 'c[2 -> null]', 'd[3 -> 2]'],
            [],
            ['d[3 -> 2]'],
            ['c[2 -> null]']));

        list.clear();
        list.addAll(['d', 'c', 'b', 'a']);
        iterator = detector.collectChanges();
        expect(iterator.moveNext()).toEqual(true);
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['d[2 -> 0]', 'c[null -> 1]', 'b[1 -> 2]', 'a[0 -> 3]'],
            ['a[0 -> 3]', 'b[1 -> 2]', 'd[2 -> 0]'],
            ['c[null -> 1]'],
            ['d[2 -> 0]', 'b[1 -> 2]', 'a[0 -> 3]'],
            []));
      });

      it('should test string by value rather than by reference', () {
        var list = ['a', 'boo'];
        detector.watch(list, null, null);
        detector.collectChanges();

        list[1] = 'b' + 'oo';

        expect(detector.collectChanges().moveNext()).toEqual(false);
      });

      it('should ignore [NaN] != [NaN]', () {
        var list = [double.NAN];
        var record = detector;
        record.watch(list, null, null);
        record.collectChanges();

        expect(detector.collectChanges().moveNext()).toEqual(false);
      });

      xit('should detect [NaN] moves', () {
        var list = [double.NAN, double.NAN];
        detector.watch(list, null, null);
        detector.collectChanges();

        list.clear();
        list.addAll(['foo', double.NAN, double.NAN]);
        var iterator = detector.collectChanges();
        expect(iterator.moveNext()).toEqual(true);
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['foo[null -> 0]', 'NaN[0 -> 1]', 'NaN[1 -> 2]'],
            ['NaN[0 -> 1]', 'NaN[1 -> 2]'],
            ['foo[null -> 0]'],
            ['NaN[0 -> 1]', 'NaN[1 -> 2]'],
            []));
      });

      it('should remove and add same item', () {
        var list = ['a', 'b', 'c'];
        var record = detector.watch(list, null, 'handler');
        var iterator;
        detector.collectChanges();

        list.remove('b');
        iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['a', 'c[2 -> 1]'],
            ['a', 'b[1 -> null]', 'c[2 -> 1]'],
            [],
            ['c[2 -> 1]'],
            ['b[1 -> null]']));

        list.insert(1, 'b');
        expect(list).toEqual(['a', 'b', 'c']);
        iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['a', 'b[null -> 1]', 'c[1 -> 2]'],
            ['a', 'c[1 -> 2]'],
            ['b[null -> 1]'],
            ['c[1 -> 2]'],
            []));
      });

      it('should support duplicates', () {
        var list = ['a', 'a', 'a', 'b', 'b'];
        var record = detector.watch(list, null, 'handler');
        detector.collectChanges();

        list.removeAt(0);
        var iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['a', 'a', 'b[3 -> 2]', 'b[4 -> 3]'],
            ['a', 'a', 'a[2 -> null]', 'b[3 -> 2]', 'b[4 -> 3]'],
            [],
            ['b[3 -> 2]', 'b[4 -> 3]'],
            ['a[2 -> null]']));
      });


      it('should support insertions/moves', () {
        var list = ['a', 'a', 'b', 'b'];
        var record = detector.watch(list, null, 'handler');
        var iterator;
        detector.collectChanges();
        list.insert(0, 'b');
        expect(list).toEqual(['b', 'a', 'a', 'b', 'b']);
        iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['b[2 -> 0]', 'a[0 -> 1]', 'a[1 -> 2]', 'b', 'b[null -> 4]'],
            ['a[0 -> 1]', 'a[1 -> 2]', 'b[2 -> 0]', 'b'],
            ['b[null -> 4]'],
            ['b[2 -> 0]', 'a[0 -> 1]', 'a[1 -> 2]'],
            []));
      });

      it('should support UnmodifiableListView', () {
        var hiddenList = [1];
        var list = new UnmodifiableListView(hiddenList);
        var record = detector.watch(list, null, 'handler');
        var iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['1[null -> 0]'],
            null,
            ['1[null -> 0]'],
            [],
            []));

        // assert no changes detected
        expect(detector.collectChanges().moveNext()).toEqual(false);

        // change the hiddenList normally this should trigger change detection
        // but because we are wrapped in UnmodifiableListView we see nothing.
        hiddenList[0] = 2;
        expect(detector.collectChanges().moveNext()).toEqual(false);
      });

      it('should bug', () {
        var list = [1, 2, 3, 4];
        var record = detector.watch(list, null, 'handler');
        var iterator;

        iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['1[null -> 0]', '2[null -> 1]', '3[null -> 2]', '4[null -> 3]'],
            null,
            ['1[null -> 0]', '2[null -> 1]', '3[null -> 2]', '4[null -> 3]'],
            [],
            []));
        detector.collectChanges();

        list.removeRange(0, 1);
        iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['2[1 -> 0]', '3[2 -> 1]', '4[3 -> 2]'],
            ['1[0 -> null]', '2[1 -> 0]', '3[2 -> 1]', '4[3 -> 2]'],
            [],
            ['2[1 -> 0]', '3[2 -> 1]', '4[3 -> 2]'],
            ['1[0 -> null]']));

        list.insert(0, 1);
        iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['1[null -> 0]', '2[0 -> 1]', '3[1 -> 2]', '4[2 -> 3]'],
            ['2[0 -> 1]', '3[1 -> 2]', '4[2 -> 3]'],
            ['1[null -> 0]'],
            ['2[0 -> 1]', '3[1 -> 2]', '4[2 -> 3]'],
            []));
      });

      it('should properly support objects with equality', () {
        FooBar.fooIds = 0;
        var list = [new FooBar('a', 'a'), new FooBar('a', 'a')];
        var record = detector.watch(list, null, 'handler');
        var iterator;

        iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['(0)a-a[null -> 0]', '(1)a-a[null -> 1]'],
            null,
            ['(0)a-a[null -> 0]', '(1)a-a[null -> 1]'],
            [],
            []));
        detector.collectChanges();

        list.removeRange(0, 1);
        iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['(1)a-a[1 -> 0]'],
            ['(0)a-a[0 -> null]', '(1)a-a[1 -> 0]'],
            [],
            ['(1)a-a[1 -> 0]'],
            ['(0)a-a[0 -> null]']));

        list.insert(0, new FooBar('a', 'a'));
        iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['(2)a-a[null -> 0]', '(1)a-a[0 -> 1]'],
            ['(1)a-a[0 -> 1]'],
            ['(2)a-a[null -> 0]'],
            ['(1)a-a[0 -> 1]'],
            []));
      });

      it('should not report unnecessary moves', () {
        var list = ['a', 'b', 'c'];
        var record = detector.watch(list, null, null);
        var iterator = detector.collectChanges();
        iterator.moveNext();

        list.clear();
        list.addAll(['b', 'a', 'c']);
        iterator = detector.collectChanges();
        iterator.moveNext();
        expect(iterator.current.currentValue, toEqualCollectionRecord(
            ['b[1 -> 0]', 'a[0 -> 1]', 'c'],
            ['a[0 -> 1]', 'b[1 -> 0]', 'c'],
            [],
            ['b[1 -> 0]', 'a[0 -> 1]'],
            []));
      });
    });

    describe('map watching', () {
      describe('previous state', () {
        it('should store on insertion', () {
          var map = {};
          var record = detector.watch(map, null, null);
          expect(detector.collectChanges().moveNext()).toEqual(false);
          var iterator;

          map['a'] = 1;
          iterator = detector.collectChanges();
          expect(iterator.moveNext()).toEqual(true);
          expect(iterator.current.currentValue, toEqualMapRecord(
              ['a[null -> 1]'],
              [],
              ['a[null -> 1]'],
              [],
              []));

          map['b'] = 2;
          iterator = detector.collectChanges();
          expect(iterator.moveNext()).toEqual(true);
          expect(iterator.current.currentValue, toEqualMapRecord(
              ['a', 'b[null -> 2]'],
              ['a'],
              ['b[null -> 2]'],
              [],
              []));
        });

        it('should handle changing key/values correctly', () {
          var map = {1: 10, 2: 20};
          var record = detector.watch(map, null, null);
          detector.collectChanges().moveNext();
          var iterator;

          map[1] = 20;
          map[2] = 10;
          iterator = detector.collectChanges();
          expect(iterator.moveNext()).toEqual(true);
          expect(iterator.current.currentValue, toEqualMapRecord(
              ['1[10 -> 20]', '2[20 -> 10]'],
              ['1[10 -> 20]', '2[20 -> 10]'],
              [],
              ['1[10 -> 20]', '2[20 -> 10]'],
              []));
        });
      });

      it('should do basic map watching', () {
        var map = {};
        var record = detector.watch(map, null, 'handler');
        expect(detector.collectChanges().moveNext()).toEqual(false);

        var changeIterator;
        map['a'] = 'A';
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue, toEqualMapRecord(
            ['a[null -> A]'],
            [],
            ['a[null -> A]'],
            [],
            []));

        map['b'] = 'B';
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue, toEqualMapRecord(
            ['a', 'b[null -> B]'],
            ['a'],
            ['b[null -> B]'],
            [],
            []));

        map['b'] = 'BB';
        map['d'] = 'D';
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue, toEqualMapRecord(
            ['a', 'b[B -> BB]', 'd[null -> D]'],
            ['a', 'b[B -> BB]'],
            ['d[null -> D]'],
            ['b[B -> BB]'],
            []));

        map.remove('b');
        expect(map).toEqual({'a': 'A', 'd':'D'});
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue, toEqualMapRecord(
            ['a', 'd'],
            ['a', 'b[BB -> null]', 'd'],
            [],
            [],
            ['b[BB -> null]']));

        map.clear();
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.current.currentValue, toEqualMapRecord(
            [],
            ['a[A -> null]', 'd[D -> null]'],
            [],
            [],
            ['a[A -> null]', 'd[D -> null]']));
      });

      it('should test string keys by value rather than by reference', () {
        var map = {'foo': 0};
        detector.watch(map, null, null);
        detector.collectChanges();

        map['f' + 'oo'] = 0;

        expect(detector.collectChanges().moveNext()).toEqual(false);
      });

      it('should test string values by value rather than by reference', () {
        var map = {'foo': 'bar'};
        detector.watch(map, null, null);
        detector.collectChanges();

        map['foo'] = 'b' + 'ar';

        expect(detector.collectChanges().moveNext()).toEqual(false);
      });

      it('should not see a NaN value as a change', () {
        var map = {'foo': double.NAN};
        var record = detector;
        record.watch(map, null, null);
        record.collectChanges();

        expect(detector.collectChanges().moveNext()).toEqual(false);
      });
    });

    describe('function watching', () {
      it('should detect no changes when watching a function', () {
        var user = new _User('marko', 'vuksanovic', 15);
        Iterator changeIterator;

        detector.watch(user, 'isUnderAge', null);
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
        expect(changeIterator.moveNext()).toEqual(false);

        user.age = 17;
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(false);

        user.age = 30;
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(false);
      });

      it('should detect change when watching a property function', () {
        var user = new _User('marko', 'vuksanovic', 30);
        Iterator changeIterator;

        detector.watch(user, 'isUnderAgeAsVariable', null);
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);

        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(false);

        user.isUnderAgeAsVariable = () => false;
        changeIterator = detector.collectChanges();
        expect(changeIterator.moveNext()).toEqual(true);
      });
    });

    describe('DuplicateMap', () {
      DuplicateMap map;
      beforeEach(() => map = new DuplicateMap());

      it('should do basic operations', () {
        var k1 = 'a';
        var r1 = new ItemRecord(k1);
        r1.currentIndex = 1;
        map.put(r1);
        expect(map.get(k1, 2)).toEqual(null);
        expect(map.get(k1, 1)).toEqual(null);
        expect(map.get(k1, 0)).toEqual(r1);
        expect(map.remove(r1)).toEqual(r1);
        expect(map.get(k1, -1)).toEqual(null);
      });

      it('should do basic operations on duplicate keys', () {
        var k1 = 'a';
        var r1 = new ItemRecord(k1);
        r1.currentIndex = 1;
        var r2 = new ItemRecord(k1);
        r2.currentIndex = 2;
        map.put(r1);
        map.put(r2);
        expect(map.get(k1, 0)).toEqual(r1);
        expect(map.get(k1, 1)).toEqual(r2);
        expect(map.get(k1, 2)).toEqual(null);
        expect(map.remove(r2)).toEqual(r2);
        expect(map.get(k1, 0)).toEqual(r1);
        expect(map.remove(r1)).toEqual(r1);
        expect(map.get(k1, 0)).toEqual(null);
      });
    });
  });
}


void main() {
  testWithGetterFactory(new DynamicFieldGetterFactory());

  testWithGetterFactory(new StaticFieldGetterFactory({
      "first": (o) => o.first,
      "age": (o) => o.age,
      "last": (o) => o.last,
      "toString": (o) => o.toString,
      "isUnderAge": (o) => o.isUnderAge,
      "isUnderAgeAsVariable": (o) => o.isUnderAgeAsVariable,
  }));
}


class _User {
  String first;
  String last;
  num age;
  var isUnderAgeAsVariable;
  List<String> list = ['foo', 'bar', 'baz'];
  Map map = {'foo': 'bar', 'baz': 'cux'};

  _User([this.first, this.last, this.age]) {
    isUnderAgeAsVariable = isUnderAge;
  }

  bool isUnderAge() {
    return age != null ? age < 18 : false;
  }
}

Matcher toEqualCollectionRecord(collection, previous, additions, moves, removals) =>
    new CollectionRecordMatcher(collection, previous,
                                additions, moves, removals);
Matcher toEqualMapRecord(map, previous, additions, changes, removals) =>
    new MapRecordMatcher(map, previous,
                         additions, changes, removals);
Matcher toEqualChanges(List changes) => new ChangeMatcher(changes);

class ChangeMatcher extends Matcher {
  List expected;

  ChangeMatcher(this.expected);

  Description describe(Description description) {
    description.add(expected.toString());
    return description;
  }

  Description describeMismatch(Iterator<Record> changes,
                               Description mismatchDescription,
                               Map matchState, bool verbose) {
    List list = [];
    while(changes.moveNext()) {
      list.add(changes.current.handler);
    }
    mismatchDescription.add(list.toString());
    return mismatchDescription;
  }

  bool matches(Iterator<Record> changes, Map matchState) {
    int count = 0;
    while(changes.moveNext()) {
      if (changes.current.handler != expected[count++]) return false;
    }
    return count == expected.length;
  }
}

abstract class _CollectionMatcher<T> extends Matcher {
  List<T> _getList(Function it) {
    var result = <T>[];
    it((item) {
      result.add(item);
    });
    return result;
  }

  bool _compareLists(String tag, List expected, List actual, List diffs) {
    var equals = true;
    Iterator iActual = actual.iterator;
    iActual.moveNext();
    T actualItem = iActual.current;
    if (expected == null) {
      expected = [];
    }
    for (String expectedItem in expected) {
      if (actualItem == null) {
        equals = false;
        diffs.add('$tag too short: $expectedItem');
      } else {
        if ("$actualItem" != expectedItem) {
          equals = false;
          diffs.add('$tag mismatch: $actualItem != $expectedItem');
        }
        iActual.moveNext();
        actualItem = iActual.current;
      }
    }
    if (actualItem != null) {
      diffs.add('$tag too long: $actualItem');
      equals = false;
    }
    return equals;
  }
}

class CollectionRecordMatcher extends _CollectionMatcher<ItemRecord> {
  final List collection;
  final List previous;
  final List additions;
  final List moves;
  final List removals;

  CollectionRecordMatcher(this.collection, this.previous,
                          this.additions, this.moves, this.removals);

  Description describeMismatch(changes, Description mismatchDescription,
                               Map matchState, bool verbose) {
    List diffs = matchState['diffs'];
    if (diffs == null) return mismatchDescription;
    mismatchDescription.add(diffs.join('\n'));
    return mismatchDescription;
  }

  Description describe(Description description) {
    add(name, collection) {
      if (collection != null) {
        description.add('$name: ${collection.join(', ')}\n   ');
      }
    }

    add('collection', collection);
    add('previous', previous);
    add('additions', additions);
    add('moves', moves);
    add('removals', removals);
    return description;
  }

  bool matches(CollectionChangeRecord changeRecord, Map matchState) {
    var diffs = matchState['diffs'] = [];
    return checkCollection(changeRecord, diffs) &&
           checkPrevious(changeRecord, diffs) &&
           checkAdditions(changeRecord, diffs) &&
           checkMoves(changeRecord, diffs) &&
           checkRemovals(changeRecord, diffs);
  }

  bool checkCollection(CollectionChangeRecord changeRecord, List diffs) {
    List items = _getList((fn) => changeRecord.forEachItem(fn));
    bool equals = _compareLists("collection", collection, items, diffs);
    int iterableLength = changeRecord.iterable.toList().length;
    if (iterableLength != items.length) {
      diffs.add('collection length mismatched: $iterableLength != ${items.length}');
      equals = false;
    }
    return equals;
  }

  bool checkPrevious(CollectionChangeRecord changeRecord, List diffs) {
    List items = _getList((fn) => changeRecord.forEachPreviousItem(fn));
    return _compareLists("previous", previous, items, diffs);
  }

  bool checkAdditions(CollectionChangeRecord changeRecord, List diffs) {
    List items = _getList((fn) => changeRecord.forEachAddition(fn));
    return _compareLists("additions", additions, items, diffs);
  }

  bool checkMoves(CollectionChangeRecord changeRecord, List diffs) {
    List items = _getList((fn) => changeRecord.forEachMove(fn));
    return _compareLists("moves", moves, items, diffs);
  }

  bool checkRemovals(CollectionChangeRecord changeRecord, List diffs) {
    List items = _getList((fn) => changeRecord.forEachRemoval(fn));
    return _compareLists("removes", removals, items, diffs);
  }
}

class MapRecordMatcher  extends _CollectionMatcher<KeyValueRecord> {
  final List map;
  final List previous;
  final List additions;
  final List changes;
  final List removals;

  MapRecordMatcher(this.map, this.previous, this.additions, this.changes, this.removals);

  Description describeMismatch(changes, Description mismatchDescription,
                               Map matchState, bool verbose) {
    List diffs = matchState['diffs'];
    if (diffs == null) return mismatchDescription;
    mismatchDescription.add(diffs.join('\n'));
    return mismatchDescription;
  }

  Description describe(Description description) {
    add(name, map) {
      if (map != null) {
        description.add('$name: ${map.join(', ')}\n   ');
      }
    }

    add('map', map);
    add('previous', previous);
    add('additions', additions);
    add('changes', changes);
    add('removals', removals);
    return description;
  }

  bool matches(MapChangeRecord changeRecord, Map matchState) {
    var diffs = matchState['diffs'] = [];
    return checkMap(changeRecord, diffs) &&
           checkPrevious(changeRecord, diffs) &&
           checkAdditions(changeRecord, diffs) &&
           checkChanges(changeRecord, diffs) &&
           checkRemovals(changeRecord, diffs);
  }

  bool checkMap(MapChangeRecord changeRecord, List diffs) {
    List items = _getList((fn) => changeRecord.forEachItem(fn));
    bool equals = _compareLists("map", map, items, diffs);
    int mapLength = changeRecord.map.length;
    if (mapLength != items.length) {
      diffs.add('map length mismatched: $mapLength != ${items.length}');
      equals = false;
    }
    return equals;
  }

  bool checkPrevious(MapChangeRecord changeRecord, List diffs) {
    List items = _getList((fn) => changeRecord.forEachPreviousItem(fn));
    return _compareLists("previous", previous, items, diffs);
  }

  bool checkAdditions(MapChangeRecord changeRecord, List diffs) {
    List items = _getList((fn) => changeRecord.forEachAddition(fn));
    return _compareLists("additions", additions, items, diffs);
  }

  bool checkChanges(MapChangeRecord changeRecord, List diffs) {
    List items = _getList((fn) => changeRecord.forEachChange(fn));
    return _compareLists("changes", changes, items, diffs);
  }

  bool checkRemovals(MapChangeRecord changeRecord, List diffs) {
    List items = _getList((fn) => changeRecord.forEachRemoval(fn));
    return _compareLists("removals", removals, items, diffs);
  }
}

class FooBar {
  static int fooIds = 0;

  int id;
  String foo, bar;

  FooBar(this.foo, this.bar) {
    id = fooIds++;
  }

  bool operator==(other) =>
      other is FooBar && foo == other.foo && bar == other.bar;

  int get hashCode => foo.hashCode ^ bar.hashCode;

  String toString() => '($id)$foo-$bar';
}
