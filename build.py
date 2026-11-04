#!/usr/bin/env python3
"""
Packs source/CajCMDR (plus the Cmdr library from Cmdr/Cmdr) into a single drop-in Roblox model: CajCMDR.rbxmx

Only needed if you change the source files. To use CajCMDR you do NOT need this script, just the .rbxmx.

    python build.py

File naming rules (same idea as Rojo):
    init.luau / init.server.luau / init.client.luau   -> the folder itself becomes a ModuleScript / Script / LocalScript
    Name.luau                                          -> ModuleScript
    Name.server.luau                                   -> Script
    Name.client.luau                                   -> LocalScript
    any other folder                                   -> Folder
"""

import os
import sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(ROOT, "source", "CajCMDR")
CMDR = os.path.join(ROOT, "Cmdr", "Cmdr")
OUTPUT = os.path.join(ROOT, "CajCMDR.rbxmx")

referent = 0


def next_referent():
    global referent
    value = f"RBX{referent:X}"
    referent += 1
    return value


def cdata(text):
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def classify(filename):
    """Returns (instance name, class name) for a source file, or None to skip it."""
    if not filename.endswith(".luau"):
        return None
    stem = filename[: -len(".luau")]
    if stem.endswith(".server"):
        return stem[: -len(".server")], "Script"
    if stem.endswith(".client"):
        return stem[: -len(".client")], "LocalScript"
    return stem, "ModuleScript"


def item(class_name, name, source, children):
    lines = [f'<Item class="{class_name}" referent="{next_referent()}">', "<Properties>"]
    lines.append(f'<string name="Name">{escape(name)}</string>')
    if source is not None:
        if class_name in ("Script", "LocalScript"):
            lines.append('<bool name="Disabled">false</bool>')
        lines.append(f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>')
    lines.append("</Properties>")
    lines.extend(children)
    lines.append("</Item>")
    return "\n".join(lines)


def read(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def build_directory(path, name, extra_children=None):
    """Builds the XML for a directory: a Folder, or a script when the directory has an init file."""
    class_name = "Folder"
    source = None
    children = []

    entries = sorted(os.listdir(path), key=lambda entry: entry.lower())
    for entry in entries:
        full = os.path.join(path, entry)

        if os.path.isdir(full):
            children.append(build_directory(full, entry))
            continue

        info = classify(entry)
        if info is None:
            continue

        child_name, child_class = info
        if child_name == "init":
            class_name = child_class
            source = read(full)
        else:
            children.append(item(child_class, child_name, read(full), []))

    children.extend(extra_children or [])
    return item(class_name, name, source, children)


def main():
    if not os.path.isdir(SOURCE):
        sys.exit(f"Missing source folder: {SOURCE}")
    if not os.path.isdir(CMDR):
        sys.exit(f"Missing Cmdr library folder: {CMDR} (clone https://github.com/evaera/Cmdr next to this script)")

    cmdr_xml = build_directory(CMDR, "Cmdr")
    root_xml = build_directory(SOURCE, "CajCMDR", [cmdr_xml])

    header = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
        '<Meta name="ExplicitAutoJoints">true</Meta>\n'
    )

    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(header)
        handle.write(root_xml)
        handle.write("\n</roblox>\n")

    size_kb = os.path.getsize(OUTPUT) / 1024
    print(f"Wrote {OUTPUT} ({size_kb:.0f} KB, {referent} instances)")


if __name__ == "__main__":
    main()
