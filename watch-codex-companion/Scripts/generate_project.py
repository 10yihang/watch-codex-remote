#!/usr/bin/env python3
"""Deterministic, dependency-free Xcode project generation; no signing or execution."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parents[1]
def uid(key): return hashlib.sha256(key.encode()).hexdigest()[:24].upper()
def q(value): return json.dumps(str(value), ensure_ascii=False)
def array(values): return '(' + ', '.join(values) + (',' if values else '') + ')'
objects = {}
def obj(key, isa, **fields):
    objects[uid(key)] = {'isa': isa, **fields}
    return uid(key)
def rawdict(fields): return '{ ' + ' '.join(f'{k} = {v};' for k,v in fields.items()) + ' }'

shared = ['Shared/Core.swift', 'Shared/Connectivity.swift', 'Shared/CompanionStore.swift', 'Shared/LiveWire.swift', 'Shared/LiveCompanionStore.swift', 'Shared/RemoteThread.swift']
remote = ['Shared/OAuthSessionWindow.swift', 'Shared/RemoteActivityGate.swift', 'Shared/RemoteSigning.swift', 'Shared/RemoteRelay.swift', 'Shared/RemoteAPI.swift', 'Shared/RemoteTokenClaims.swift']
sources = {'Phone': shared + remote + ['iPhone/PhoneApp.swift', 'iPhone/PhoneRootView.swift', 'iPhone/RemoteDeviceKey.swift', 'iPhone/RemoteDiagnostics.swift', 'iPhone/CodexPlanOAuth.swift', 'iPhone/CodexPlanTokenStore.swift', 'iPhone/CodexOAuthCallbackServer.swift', 'iPhone/CodexOAuthSafariPresenter.swift', 'iPhone/RemoteConnectionJournal.swift', 'iPhone/RemoteConnectionController.swift', 'iPhone/LiveRemoteView.swift'],
           'Watch': shared + ['Watch/WatchApp.swift', 'Watch/WatchRootView.swift', 'Watch/LiveWatchView.swift']}
for source in sorted(set(sum(sources.values(), []))):
    obj(source, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=q(source), sourceTree=q('<group>'))
for folder in ['iPhone', 'Watch']:
    path = folder + '/Info.plist'
    obj(path, 'PBXFileReference', lastKnownFileType='text.plist.xml', path=q(path), sourceTree=q('<group>'))
obj('assets','PBXFileReference',lastKnownFileType='folder.assetcatalog',path=q('Shared/Assets.xcassets'),sourceTree=q('<group>'))
for name in ['Phone','Watch']:
    obj('product'+name,'PBXFileReference',explicitFileType='wrapper.application',includeInIndex='0',path=q('WatchCodex'+name+'.app'),sourceTree='BUILT_PRODUCTS_DIR')
    builds=[]
    for source in sources[name]:
        builds.append(obj(name+source,'PBXBuildFile', fileRef=uid(source)))
    obj('sources'+name,'PBXSourcesBuildPhase',buildActionMask='2147483647',files=array(builds),runOnlyForDeploymentPostprocessing='0')
    obj('frameworks'+name,'PBXFrameworksBuildPhase',buildActionMask='2147483647',files='()',runOnlyForDeploymentPostprocessing='0')
    obj('assetBuild'+name,'PBXBuildFile',fileRef=uid('assets'))
    obj('resources'+name,'PBXResourcesBuildPhase',buildActionMask='2147483647',files=array([uid('assetBuild'+name)]),runOnlyForDeploymentPostprocessing='0')
    configs=[]
    for mode in ['Debug','Release']:
        settings={
            'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':q('WatchAccent' if name=='Watch' else 'AccentColor'), 'CODE_SIGN_STYLE':q('Automatic'), 'DEVELOPMENT_TEAM':q(''),
            'PRODUCT_BUNDLE_IDENTIFIER':q('$(WATCH_CODEX_PHONE_BUNDLE_ID)' + ('.watchkitapp' if name=='Watch' else '')),
            'PRODUCT_NAME':q('$(TARGET_NAME)'), 'INFOPLIST_FILE':q(('Watch' if name=='Watch' else 'iPhone')+'/Info.plist'),
            'GENERATE_INFOPLIST_FILE':'NO', 'SWIFT_VERSION':'5.0', 'SWIFT_STRICT_CONCURRENCY':'minimal',
            'SWIFT_EMIT_LOC_STRINGS':'YES', 'MARKETING_VERSION':'0.1.0','CURRENT_PROJECT_VERSION':'1',
            'SDKROOT':'watchos' if name=='Watch' else 'iphoneos',
            'SUPPORTED_PLATFORMS':q('watchos watchsimulator' if name=='Watch' else 'iphoneos iphonesimulator'),
            'TARGETED_DEVICE_FAMILY':q('4' if name=='Watch' else '1'),
            'WATCHOS_DEPLOYMENT_TARGET' if name=='Watch' else 'IPHONEOS_DEPLOYMENT_TARGET':'10.0' if name=='Watch' else '17.0',
            'LD_RUNPATH_SEARCH_PATHS':array([q('$(inherited)'),q('@executable_path/Frameworks')]),
            'SWIFT_OPTIMIZATION_LEVEL':q('-Onone' if mode=='Debug' else '-O'),
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS':q('DEBUG $(inherited)' if mode=='Debug' else '$(inherited)'),
        }
        if name=='Watch': settings['SKIP_INSTALL']='YES'
        else: settings['SUPPORTS_MACCATALYST']='NO'
        configs.append(obj(name+mode,'XCBuildConfiguration',buildSettings=rawdict(settings),name=q(mode)))
    obj('config'+name,'XCConfigurationList',buildConfigurations=array(configs),defaultConfigurationIsVisible='0',defaultConfigurationName='Release')

obj('embedWatchFile','PBXBuildFile',fileRef=uid('productWatch'),settings=rawdict({'ATTRIBUTES':array(['RemoveHeadersOnCopy'])}))
obj('embedWatch','PBXCopyFilesBuildPhase',buildActionMask='2147483647',dstPath=q('$(CONTENTS_FOLDER_PATH)/Watch'),dstSubfolderSpec='16',files=array([uid('embedWatchFile')]),name=q('Embed Watch Content'),runOnlyForDeploymentPostprocessing='0')
obj('watchProxy','PBXContainerItemProxy',containerPortal=uid('project'),proxyType='1',remoteGlobalIDString=uid('targetWatch'),remoteInfo=q('WatchCodexWatch'))
obj('watchDependency','PBXTargetDependency',target=uid('targetWatch'),targetProxy=uid('watchProxy'))
for name in ['Phone','Watch']:
    phases=[uid('sources'+name),uid('frameworks'+name),uid('resources'+name)]
    if name=='Phone': phases.append(uid('embedWatch'))
    obj('target'+name,'PBXNativeTarget',buildConfigurationList=uid('config'+name),buildPhases=array(phases),buildRules='()',dependencies=array([uid('watchDependency')] if name=='Phone' else []),name=q('WatchCodex'+name),productName=q('WatchCodex'+name),productReference=uid('product'+name),productType=q('com.apple.product-type.application'))
obj('products','PBXGroup',children=array([uid('productPhone'),uid('productWatch')]),name='Products',sourceTree=q('<group>'))
obj('main','PBXGroup',children=array([uid(s) for s in sorted(set(sum(sources.values(), [])))]+[uid('iPhone/Info.plist'),uid('Watch/Info.plist'),uid('assets'),uid('products')]),sourceTree=q('<group>'))
projectconfigs=[]
for mode in ['Debug','Release']:
    projectconfigs.append(obj('project'+mode,'XCBuildConfiguration',buildSettings=rawdict({'WATCH_CODEX_PHONE_BUNDLE_ID':q('org.example.watchcodex'),'CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','ENABLE_STRICT_OBJC_MSGSEND':'YES','DEBUG_INFORMATION_FORMAT':q('dwarf' if mode=='Debug' else 'dwarf-with-dsym')}),name=q(mode)))
obj('projectconfig','XCConfigurationList',buildConfigurations=array(projectconfigs),defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
obj('project','PBXProject',attributes=rawdict({'BuildIndependentTargetsInParallel':'YES','LastSwiftUpdateCheck':'1600','LastUpgradeCheck':'1600'}),buildConfigurationList=uid('projectconfig'),compatibilityVersion=q('Xcode 14.0'),developmentRegion='zh-Hans',hasScannedForEncodings='0',knownRegions=array([q('zh-Hans'),'en','Base']),mainGroup=uid('main'),productRefGroup=uid('products'),projectDirPath=q(''),projectRoot=q(''),targets=array([uid('targetPhone'),uid('targetWatch')]))
lines=['// !$*UTF8*$!','{','archiveVersion = 1;','classes = {};','objectVersion = 56;','objects = {']
for key, fields in objects.items(): lines.append(key+' = '+rawdict(fields)+';')
lines += ['};',f'rootObject = {uid("project")};','}']
(ROOT/'WatchCodex.xcodeproj/project.pbxproj').write_text('\n'.join(lines)+'\n')
base={'CFBundleDevelopmentRegion':'zh-Hans','CFBundleDisplayName':'Codex Remote','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)'}
phone={**base,'CodexOAuthEnabled':True,'CodexOAuthClientID':'app_EMoamEEZ73f0CkXaXp7hrann','CodexOAuthScope':'openid profile email offline_access api.connectors.read api.connectors.invoke','NSFaceIDUsageDescription':'通过系统身份验证使用本机 Codex Remote 控制器密钥。','LSRequiresIPhoneOS':True,'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']}
watch={**base,'WKApplication':True,'WKCompanionAppBundleIdentifier':'$(WATCH_CODEX_PHONE_BUNDLE_ID)','WKRunsIndependentlyOfCompanionApp':False}
for folder, value in [('iPhone',phone),('Watch',watch)]:
    (ROOT/folder/'Info.plist').write_bytes(plistlib.dumps(value,sort_keys=False))
for name in ['Phone','Watch']:
    target=uid('target'+name)
    ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="WatchCodex{name}.app" BlueprintName="WatchCodex{name}" ReferencedContainer="container:WatchCodex.xcodeproj"/>'
    scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
    (ROOT/f'WatchCodex.xcodeproj/xcshareddata/xcschemes/WatchCodex{name}.xcscheme').write_text(scheme)
print('Generated WatchCodex.xcodeproj (2 application targets, 2 shared schemes).')
