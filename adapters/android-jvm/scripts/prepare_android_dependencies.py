#!/usr/bin/env python3
# [Android-JVMアダプタ] Android依存ライブラリ（billing等）のダウンロード・展開
# Downloads and extracts Android AAR/JAR dependencies from Google Maven + Maven Central.
# Called by prepare-android-dependencies.sh.
import argparse
import pathlib
import urllib.error
import urllib.request
import zipfile
import xml.etree.ElementTree as ET


REPOSITORIES = (
    "https://dl.google.com/dl/android/maven2",
    "https://repo1.maven.org/maven2",
)
MAVEN_NS = {"m": "http://maven.apache.org/POM/4.0.0"}


class Coordinate:
    def __init__(self, group_id, artifact_id, version, packaging):
        self.group_id = group_id
        self.artifact_id = artifact_id
        self.version = normalize_version(version)
        self.packaging = packaging or "jar"

    def key(self):
        return (self.group_id, self.artifact_id, self.version, self.packaging)

    def base_path(self):
        group_path = self.group_id.replace(".", "/")
        return f"{group_path}/{self.artifact_id}/{self.version}"

    def file_name(self):
        return f"{self.artifact_id}-{self.version}.{self.packaging}"

    def pom_name(self):
        return f"{self.artifact_id}-{self.version}.pom"

    def label(self):
        return f"{self.group_id}:{self.artifact_id}:{self.version}@{self.packaging}"


def download(url, path):
    if path.is_file():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as response:
        path.write_bytes(response.read())


def download_from_repositories(relative_path, path):
    last_error = None
    for repository in REPOSITORIES:
        url = f"{repository}/{relative_path}"
        try:
            download(url, path)
            return
        except urllib.error.HTTPError as error:
            last_error = error
    raise SystemExit(f"Unable to download {relative_path}: {last_error}")


def text(element, path):
    found = element.find(path, MAVEN_NS)
    return found.text.strip() if found is not None and found.text else ""


def dependency_type(dependency):
    value = text(dependency, "m:type")
    return value or "jar"


def normalize_version(version):
    if version.startswith("[") and version.endswith("]"):
        return version[1:-1]
    return version


def version_key(version):
    parts = []
    for part in version.replace("-", ".").split("."):
        if part.isdigit():
            parts.append((1, int(part)))
        else:
            parts.append((0, part))
    return parts


def class_jar_name(coordinate, suffix=""):
    group = coordinate.group_id.replace(".", "_")
    extra = f"-{suffix}" if suffix else ""
    return f"{group}__{coordinate.artifact_id}-{coordinate.version}{extra}.jar"


def dependency_scope(dependency):
    value = text(dependency, "m:scope")
    return value or "compile"


def parse_dependencies(pom_path):
    root = ET.parse(pom_path).getroot()
    dependencies = []
    for dependency in root.findall("m:dependencies/m:dependency", MAVEN_NS):
        scope = dependency_scope(dependency)
        optional = text(dependency, "m:optional")
        if scope not in ("compile", "runtime") or optional == "true":
            continue
        dependencies.append(Coordinate(
            text(dependency, "m:groupId"),
            text(dependency, "m:artifactId"),
            text(dependency, "m:version"),
            dependency_type(dependency),
        ))
    return dependencies


def parse_packaging(pom_path):
    root = ET.parse(pom_path).getroot()
    packaging = text(root, "m:packaging")
    return packaging or "jar"


def extract_classes(coordinate, artifact_path, output_dir, extracted_outputs):
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / class_jar_name(coordinate)
    if coordinate.packaging == "jar":
        output.write_bytes(artifact_path.read_bytes())
        extracted_outputs.append((coordinate, output))
        return
    if coordinate.packaging != "aar":
        return
    extracted_dir = output_dir.parent / "extracted" / f"{coordinate.artifact_id}-{coordinate.version}"
    if extracted_dir.exists():
        for child in extracted_dir.iterdir():
            if child.is_file():
                child.unlink()
    extracted_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(artifact_path) as archive:
        archive.extractall(extracted_dir)
    classes = extracted_dir / "classes.jar"
    if classes.is_file():
        output.write_bytes(classes.read_bytes())
        extracted_outputs.append((coordinate, output))
    libs = extracted_dir / "libs"
    if libs.is_dir():
        for jar in libs.glob("*.jar"):
            lib_output = output_dir / class_jar_name(coordinate, jar.stem)
            lib_output.write_bytes(jar.read_bytes())
            extracted_outputs.append((coordinate, lib_output))


def remember_selected(coordinate, selected_versions):
    key = (coordinate.group_id, coordinate.artifact_id)
    current = selected_versions.get(key)
    if current is None or version_key(coordinate.version) > version_key(current):
        selected_versions[key] = coordinate.version


def remove_lower_version_outputs(extracted_outputs, selected_versions):
    for coordinate, path in extracted_outputs:
        selected = selected_versions[(coordinate.group_id, coordinate.artifact_id)]
        if coordinate.version != selected and path.exists():
            path.unlink()


def remove_redundant_kotlin_stdlib_outputs(extracted_outputs, selected_versions):
    stdlib_version = selected_versions.get(("org.jetbrains.kotlin", "kotlin-stdlib"))
    if stdlib_version is None or version_key(stdlib_version) < version_key("1.8.0"):
        return
    redundant = (
        ("org.jetbrains.kotlin", "kotlin-stdlib-jdk7"),
        ("org.jetbrains.kotlin", "kotlin-stdlib-jdk8"),
    )
    for coordinate, path in extracted_outputs:
        if (coordinate.group_id, coordinate.artifact_id) in redundant and path.exists():
            path.unlink()


def resolve(coordinate, deps_dir, seen, selected_versions, extracted_outputs):
    if coordinate.key() in seen:
        return
    seen.add(coordinate.key())
    remember_selected(coordinate, selected_versions)

    pom_path = deps_dir / "poms" / coordinate.base_path() / coordinate.pom_name()
    download_from_repositories(f"{coordinate.base_path()}/{coordinate.pom_name()}", pom_path)
    packaging = coordinate.packaging
    if packaging == "jar":
        packaging = parse_packaging(pom_path)
        coordinate = Coordinate(coordinate.group_id, coordinate.artifact_id, coordinate.version, packaging)
        remember_selected(coordinate, selected_versions)
    artifact_path = deps_dir / "downloads" / coordinate.base_path() / coordinate.file_name()
    download_from_repositories(f"{coordinate.base_path()}/{coordinate.file_name()}", artifact_path)
    extract_classes(coordinate, artifact_path, deps_dir / "classes", extracted_outputs)

    for dependency in parse_dependencies(pom_path):
        resolve(dependency, deps_dir, seen, selected_versions, extracted_outputs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--deps-dir", required=True)
    parser.add_argument("--billing-version", default="9.0.0")
    args = parser.parse_args()

    deps_dir = pathlib.Path(args.deps_dir)
    classes_dir = deps_dir / "classes"
    if classes_dir.is_dir():
        for jar in classes_dir.glob("*.jar"):
            jar.unlink()
    root = Coordinate("com.android.billingclient", "billing", args.billing_version, "aar")
    selected_versions = {}
    extracted_outputs = []
    resolve(root, deps_dir, set(), selected_versions, extracted_outputs)
    remove_lower_version_outputs(extracted_outputs, selected_versions)
    remove_redundant_kotlin_stdlib_outputs(extracted_outputs, selected_versions)
    print(f"Prepared {root.label()} and transitive Android dependencies in {deps_dir}")


if __name__ == "__main__":
    main()
