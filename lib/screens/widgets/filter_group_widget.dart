import 'package:flutter/material.dart';
import 'package:nami/utilities/hive/custom_group.dart';
import 'package:nami/utilities/hive/mitglied.dart';
import 'package:nami/utilities/mitglied.filterAndSort.dart';
import 'package:nami/utilities/stufe.dart';
import 'package:provider/provider.dart';

class FilterGroupWidget extends StatelessWidget {
  const FilterGroupWidget({super.key, required this.mitglieder});

  final List<Mitglied> mitglieder;

  @override
  Widget build(BuildContext context) {
    final Map<String, CustomGroup> gruppen =
        Provider.of<MemberListSettingsHandler>(
          context,
        ).filterOptions.filterGroup;

    // Zeige keine Gruppe an, die keine Mitglieder haben
    final Map<String, CustomGroup> customGruppen = {};

    gruppen.forEach((key, value) {
      if (!value.static ||
          (value.stufe != null &&
              mitglieder.any(
                (mitglied) =>
                    value.stufe == mitglied.currentStufeWithoutLeiter ||
                    (value.stufe == Stufe.LEITER &&
                        mitglied.isMitgliedLeiter()),
              ))) {
        customGruppen[key] = value;
      }
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: customGruppen.entries.map((entry) {
            final String groupName = entry.key;
            final CustomGroup group = entry.value;

            final Widget groupImage = (group.stufe == null)
                ? Icon(group.icon, semanticLabel: '$groupName Filter')
                : Image.asset(
                    group.stufe!.imagePath ?? Stufe.LEITER.imagePath!,
                    semanticLabel: '$groupName Filter',
                    width: 30.0,
                    height: 30.0,
                    cacheHeight: 100,
                  );

            return GestureDetector(
              onTap: () {
                Provider.of<MemberListSettingsHandler>(
                  context,
                  listen: false,
                ).updateFilterGroupActive(groupName, !group.active);
              },
              child: Container(
                width: 50.0,
                height: 50.0,
                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: group.active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.secondaryContainer,
                ),
                child: Center(child: groupImage),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
