#!/usr/bin/env python3
"""Insert a release into the Sparkle appcast the app polls for updates.

Sparkle ships `generate_appcast`, which builds a feed from a directory holding every
released archive. gaugent publishes its disk images as GitHub release assets, so their
URLs carry a per-release tag and no single download prefix can describe them, and the
archives are not kept around after a release. This writes one entry at a time instead.
"""

import argparse
import base64
import re
from urllib.parse import urlparse
import sys
import xml.etree.ElementTree as ElementTree
from datetime import datetime, timezone
from pathlib import Path

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ElementTree.register_namespace("sparkle", SPARKLE_NAMESPACE)


def sparkle(name):
    return f"{{{SPARKLE_NAMESPACE}}}{name}"


def empty_feed(title):
    rss = ElementTree.Element("rss", {"version": "2.0"})
    channel = ElementTree.SubElement(rss, "channel")
    ElementTree.SubElement(channel, "title").text = title
    return ElementTree.ElementTree(rss)


def load_feed(path, title):
    if not path.exists():
        return empty_feed(title)
    try:
        return ElementTree.parse(path)
    except ElementTree.ParseError as error:
        sys.exit(f"{path} is not valid XML: {error}")


def build_number(item):
    element = item.find(sparkle("version"))
    if element is None:
        enclosure = item.find("enclosure")
        element = enclosure if enclosure is not None else None
        return element.get(sparkle("version"), "") if element is not None else ""
    return element.text or ""


def as_sortable(version):
    """Orders build numbers made of period-separated integers."""
    try:
        return [int(part) for part in version.split(".")]
    except ValueError:
        return [-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", required=True, type=Path)
    parser.add_argument("--version", required=True, help="CFBundleVersion; what Sparkle compares")
    parser.add_argument("--short-version", help="Release label shown to the user")
    parser.add_argument("--url", help="Download URL for the disk image")
    parser.add_argument("--length", help="Size of the disk image in bytes")
    parser.add_argument("--signature", help="EdDSA signature from sign_update")
    parser.add_argument("--minimum-system-version", default="14.0")
    parser.add_argument("--release-notes-link", default=None)
    parser.add_argument("--title", default="gaugent")
    parser.add_argument("--keep", type=int, default=10, help="How many releases to retain")
    parser.add_argument("--validate-only", action="store_true")
    arguments = parser.parse_args()
    if not re.fullmatch(r"[1-9][0-9]*", arguments.version):
        sys.exit("Build number must be a positive integer")

    tree = load_feed(arguments.appcast, arguments.title)
    channel = tree.getroot().find("channel")
    if channel is None:
        sys.exit(f"{arguments.appcast} has no <channel>")

    newest = max(
        (as_sortable(build_number(item)) for item in channel.findall("item")),
        default=[0],
    )
    if as_sortable(arguments.version) <= newest:
        sys.exit(
            f"Build number {arguments.version} is not greater than the newest already "
            f"published ({'.'.join(str(part) for part in newest)}). Sparkle compares "
            "CFBundleVersion, so it must increase with every release."
        )

    if arguments.validate_only:
        return
    if not arguments.short_version or not arguments.url or not arguments.signature or not arguments.length:
        sys.exit("Release label, URL, signature, and length are required")
    if urlparse(arguments.url).scheme != "https" or not urlparse(arguments.url).netloc:
        sys.exit("Download URL must use HTTPS")
    if "-local.dmg" in arguments.url:
        sys.exit("Local candidates cannot be published to the update feed")
    if not arguments.length.isdigit() or int(arguments.length) <= 0:
        sys.exit("Length must be positive")
    try:
        if len(base64.b64decode(arguments.signature, validate=True)) != 64:
            raise ValueError()
    except ValueError:
        sys.exit("Invalid EdDSA signature")
    item = ElementTree.Element("item")
    ElementTree.SubElement(item, "title").text = arguments.short_version
    ElementTree.SubElement(item, sparkle("version")).text = arguments.version
    ElementTree.SubElement(item, sparkle("shortVersionString")).text = arguments.short_version
    ElementTree.SubElement(item, sparkle("minimumSystemVersion")).text = arguments.minimum_system_version
    ElementTree.SubElement(item, "pubDate").text = datetime.now(timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S +0000"
    )
    if arguments.release_notes_link:
        ElementTree.SubElement(item, sparkle("fullReleaseNotesLink")).text = arguments.release_notes_link
    ElementTree.SubElement(
        item,
        "enclosure",
        {
            "url": arguments.url,
            "length": arguments.length,
            "type": "application/octet-stream",
            sparkle("edSignature"): arguments.signature,
        },
    )

    items = channel.findall("item")
    for existing in items:
        channel.remove(existing)
    ordered = sorted(
        [item] + items,
        key=lambda entry: as_sortable(build_number(entry)),
        reverse=True,
    )[: arguments.keep]
    for entry in ordered:
        channel.append(entry)

    ElementTree.indent(tree, space="    ")
    arguments.appcast.parent.mkdir(parents=True, exist_ok=True)
    temporary = arguments.appcast.with_suffix(".xml.tmp")
    tree.write(temporary, encoding="UTF-8", xml_declaration=True)
    temporary.replace(arguments.appcast)
    print(f"Wrote {arguments.short_version} (build {arguments.version}) to {arguments.appcast}")


if __name__ == "__main__":
    main()
