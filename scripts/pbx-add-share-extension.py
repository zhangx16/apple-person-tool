#!/usr/bin/env python3
"""Add ShareExtension target + embed phase to PersonalToolbox.xcodeproj."""
from pathlib import Path
import re

ROOT = Path("/root/PersonalToolbox")
PBX = ROOT / "PersonalToolbox.xcodeproj" / "project.pbxproj"
text = PBX.read_text()

if "ShareExtension" in text and "ShareViewController.swift in Sources" in text:
    print("ShareExtension already present")
    raise SystemExit(0)

ids = [int(m, 16) for m in re.findall(r"000000000000000000000([0-9A-F]{3})\b", text)]
n = max(ids) + 1

def hid():
    global n
    s = f"{n:03X}"
    n += 1
    return f"000000000000000000000{s}"

# IDs
file_ref_swift = hid()
file_ref_plist = hid()
file_ref_ent = hid()
file_ref_product = hid()
build_swift = hid()
build_plist = hid()  # not in compile sources usually for extension info
build_embed = hid()  # PBXBuildFile for embed
group_share = hid()
sources_phase = hid()
resources_phase = hid()
frameworks_phase = hid()
target_id = hid()
config_list_target = hid()
config_debug = hid()
config_release = hid()
container_proxy = hid()
target_dep = hid()
copy_files_phase = hid()  # Embed Foundation Extensions
main_target = "000000000000000000000001"  # will resolve

# Find main native target id
m = re.search(
    r"([0-9A-F]{24}) /\* PersonalToolbox \*/ = \{\s*isa = PBXNativeTarget;",
    text,
)
if not m:
    # alternate spacing
    m = re.search(
        r"(/\* Begin PBXNativeTarget section \*/\s*)([0-9A-F]{24}) /\* PersonalToolbox \*/ = \{",
        text,
    )
    if m:
        main_target = m.group(2)
    else:
        # scan
        m2 = re.search(r"([0-9A-F]{24}) /\* PersonalToolbox \*/ = \{\n\t\t\tisa = PBXNativeTarget;", text)
        if not m2:
            raise SystemExit("main target not found")
        main_target = m2.group(1)
else:
    main_target = m.group(1)

print("main_target", main_target)

# PBXBuildFile
bf = f"""
\t\t{build_swift} /* ShareViewController.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_swift} /* ShareViewController.swift */; }};
\t\t{build_embed} /* ShareExtension.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {file_ref_product} /* ShareExtension.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
"""
text = text.replace("/* End PBXBuildFile section */", bf + "/* End PBXBuildFile section */")

# PBXFileReference
fr = f"""
\t\t{file_ref_swift} /* ShareViewController.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareViewController.swift; sourceTree = "<group>"; }};
\t\t{file_ref_plist} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
\t\t{file_ref_ent} /* ShareExtension.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = ShareExtension.entitlements; sourceTree = "<group>"; }};
\t\t{file_ref_product} /* ShareExtension.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = ShareExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
"""
text = text.replace("/* End PBXFileReference section */", fr + "/* End PBXFileReference section */")

# Also need ShareHandoff.swift compiled into extension - use same file via file ref already in main?
# Duplicate compile: add build file pointing to main ShareHandoff if exists
share_handoff_ref = None
m = re.search(r"([0-9A-F]{24}) /\* ShareHandoff.swift \*/ = \{isa = PBXFileReference", text)
if m:
    share_handoff_ref = m.group(1)
else:
    # will be added separately by other script - create file ref if missing
    share_handoff_ref = hid()
    share_handoff_build_main = hid()
    share_handoff_build_ext = hid()
    text = text.replace(
        "/* End PBXBuildFile section */",
        f"\t\t{share_handoff_build_main} /* ShareHandoff.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {share_handoff_ref} /* ShareHandoff.swift */; }};\n"
        f"\t\t{share_handoff_build_ext} /* ShareHandoff.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {share_handoff_ref} /* ShareHandoff.swift */; }};\n"
        "/* End PBXBuildFile section */",
    )
    text = text.replace(
        "/* End PBXFileReference section */",
        f"\t\t{share_handoff_ref} /* ShareHandoff.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareHandoff.swift; sourceTree = \"<group>\"; }};\n"
        "/* End PBXFileReference section */",
    )
    # add to Core group
    text = text.replace(
        "0000000000000000000001C8 /* LocalNotifier.swift */,\n",
        f"0000000000000000000001C8 /* LocalNotifier.swift */,\n\t\t\t\t{share_handoff_ref} /* ShareHandoff.swift */,\n",
    )
    # main sources
    text = text.replace(
        "0000000000000000000001C9 /* LocalNotifier.swift in Sources */,\n",
        f"0000000000000000000001C9 /* LocalNotifier.swift in Sources */,\n\t\t\t\t{share_handoff_build_main} /* ShareHandoff.swift in Sources */,\n",
    )

# Group ShareExtension
group = f"""
\t\t{group_share} /* ShareExtension */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{file_ref_swift} /* ShareViewController.swift */,
\t\t\t\t{file_ref_plist} /* Info.plist */,
\t\t\t\t{file_ref_ent} /* ShareExtension.entitlements */,
\t\t\t);
\t\t\tpath = ShareExtension;
\t\t\tsourceTree = "<group>";
\t\t}};
"""
text = text.replace("/* End PBXGroup section */", group + "/* End PBXGroup section */")

# Add group + product to root project children and Products
# Find Products group
text = text.replace(
    "/* PersonalToolbox.app */,\n",
    f"/* PersonalToolbox.app */,\n\t\t\t\t{file_ref_product} /* ShareExtension.appex */,\n",
)
# Root project group - add ShareExtension next to PersonalToolbox folder group
# 000000000000000000000300 is often main group
m = re.search(r"(000000000000000000000300 /\* PersonalToolbox \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)", text)
if m:
    text = text.replace(m.group(1), m.group(1) + f"\t\t\t\t{group_share} /* ShareExtension */,\n")
else:
    # insert into first group that contains Features
    text = text.replace(
        "000000000000000000000306 /* Features */,\n",
        f"{group_share} /* ShareExtension */,\n\t\t\t\t000000000000000000000306 /* Features */,\n",
    )

# Sources / Frameworks / Resources phases for extension
phases = f"""
\t\t{sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{build_swift} /* ShareViewController.swift in Sources */,
\t\t\t\t{share_handoff_build_ext} /* ShareHandoff.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{copy_files_phase} /* Embed Foundation Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{build_embed} /* ShareExtension.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""
text = text.replace("/* End PBXSourcesBuildPhase section */", phases + "/* End PBXSourcesBuildPhase section */")

# Native target
target = f"""
\t\t{target_id} /* ShareExtension */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {config_list_target} /* Build configuration list for PBXNativeTarget "ShareExtension" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase} /* Sources */,
\t\t\t\t{frameworks_phase} /* Frameworks */,
\t\t\t\t{resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = ShareExtension;
\t\t\tproductName = ShareExtension;
\t\t\tproductReference = {file_ref_product} /* ShareExtension.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t}};
"""
text = text.replace("/* End PBXNativeTarget section */", target + "/* End PBXNativeTarget section */")

# Dependency + embed on main target
dep = f"""
\t\t{container_proxy} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = 000000000000000000000000 /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {target_id};
\t\t\tremoteInfo = ShareExtension;
\t\t}};
\t\t{target_dep} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {target_id} /* ShareExtension */;
\t\t\ttargetProxy = {container_proxy} /* PBXContainerItemProxy */;
\t\t}};
"""
if "/* End PBXTargetDependency section */" in text:
    text = text.replace("/* End PBXTargetDependency section */", dep + "/* End PBXTargetDependency section */")
else:
    text = text.replace(
        "/* End PBXNativeTarget section */",
        "/* End PBXNativeTarget section */\n/* Begin PBXTargetDependency section */\n"
        + dep
        + "/* End PBXTargetDependency section */\n",
    )

# Patch main target buildPhases and dependencies
main_block = re.search(
    rf"{main_target} /\* PersonalToolbox \*/ = \{{.*?\n\t\t\}};",
    text,
    re.S,
)
if not main_block:
    raise SystemExit("cannot find main target block")
block = main_block.group(0)
if "Embed Foundation Extensions" not in block:
    block2 = block.replace(
        "buildPhases = (",
        f"buildPhases = (\n\t\t\t\t{copy_files_phase} /* Embed Foundation Extensions */,",
    )
    if "dependencies = (" in block2 and target_dep not in block2:
        block2 = block2.replace(
            "dependencies = (",
            f"dependencies = (\n\t\t\t\t{target_dep} /* PBXTargetDependency */,",
        )
    text = text.replace(block, block2)

# Project targets list
text = text.replace(
    "targets = (\n\t\t\t\t" + main_target,
    f"targets = (\n\t\t\t\t{main_target},\n\t\t\t\t{target_id} /* ShareExtension */",
)
# if already has comma style
if f"{target_id} /* ShareExtension */" not in text.split("targets =")[1][:500]:
    text = re.sub(
        r"(targets = \(\n\t\t\t\t[0-9A-F]{24} /\* PersonalToolbox \*/)",
        rf"\1,\n\t\t\t\t{target_id} /* ShareExtension */",
        text,
        count=1,
    )

# Build configurations for extension
xc = f"""
\t\t{config_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements;
\t\t\t\tCODE_SIGN_IDENTITY = "iPhone Distribution";
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tCURRENT_PROJECT_VERSION = 7;
\t\t\t\tDEVELOPMENT_TEAM = CTSQLK944L;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = ShareExtension/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.3;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = app.parsnip6345.lake8262.share;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{config_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements;
\t\t\t\tCODE_SIGN_IDENTITY = "iPhone Distribution";
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tCURRENT_PROJECT_VERSION = 7;
\t\t\t\tDEVELOPMENT_TEAM = CTSQLK944L;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = ShareExtension/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.3;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = app.parsnip6345.lake8262.share;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
"""
text = text.replace("/* End XCBuildConfiguration section */", xc + "/* End XCBuildConfiguration section */")

xclist = f"""
\t\t{config_list_target} /* Build configuration list for PBXNativeTarget "ShareExtension" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{config_debug} /* Debug */,
\t\t\t\t{config_release} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
"""
text = text.replace("/* End XCConfigurationList section */", xclist + "/* End XCConfigurationList section */")

# Main app entitlements + version bump
text = text.replace(
    "GENERATE_INFOPLIST_FILE = NO;\n\t\t\t\tINFOPLIST_FILE = PersonalToolbox/Resources/Info.plist;",
    "CODE_SIGN_ENTITLEMENTS = PersonalToolbox/PersonalToolbox.entitlements;\n\t\t\t\tGENERATE_INFOPLIST_FILE = NO;\n\t\t\t\tINFOPLIST_FILE = PersonalToolbox/Resources/Info.plist;",
)
text = text.replace("CURRENT_PROJECT_VERSION = 6;", "CURRENT_PROJECT_VERSION = 7;")
text = text.replace("MARKETING_VERSION = 1.3;", "MARKETING_VERSION = 1.3;")

PBX.write_text(text)
print("ShareExtension target added", target_id)
print("next id", hex(n))
