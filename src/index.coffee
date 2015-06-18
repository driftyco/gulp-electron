
fs = require 'fs'
grs = require 'grs'
path = require 'path'
async = require 'async'
wrench = require 'wrench'
Promise = require 'bluebird'
mv = require 'mv'
mvAsync = Promise.promisify mv
rm = require 'rimraf'
rmAsync = Promise.promisify rm
winresourcer = Promise.promisify(require 'winresourcer')
util = require 'gulp-util'
asar = require 'asar'
chalk = require 'chalk'
Decompress = require 'decompress-zip'
PluginError = util.PluginError
through = require 'through2'
childProcess = require 'child_process'
ProgressBar = require 'progress'
File = require 'vinyl'
plist = require 'plist'


PLUGIN_NAME = 'gulp-electron'

module.exports = electron = (options) ->
  # Options should be like
  #  cache
  #  src
  #  packageJson
  #  release
  #  platforms: ['darwin', 'win32', 'linux']
  #  apm
  #  rebuild
  #  asar
  #  packaging
  #  symbols
  #  version
  #  repo
  PLUGIN_NAME = 'gulp-electron'
  options = (options or {})

  if not options.release or not options.version or
   not options.src or not options.cache
    throw new PluginError PLUGIN_NAME, 'Miss version or release path.'
  if path.resolve(options.src) is path.resolve(".")
    throw new PluginError PLUGIN_NAME, 'src path can not root path.'

  packageJson = options.packageJson
  if typeof options.packageJson is 'string'
    packageJson = require(packageJson)
  options.platforms ?= ['darwin']
  options.apm ?= getApmPath()
  options.generateIconPath ?= null
  options.icnsPath ?= null
  options.iconPath ?= null
  options.symbols ?= false
  options.rebuild ?= false
  options.asar ?= false
  options.packaging ?= true
  options.ext ?= 'zip'

  options.displayName ?= "Electron"
  options.bundleId ?= "com.github.electron"

  options.platforms = [options.platforms] if typeof options.platforms is 'string'

  bufferContents = (file, enc, cb) ->
    src = file
    cb()

  endStream = (callback) ->
    push = @push
    platforms = ['darwin',
    'win32',
    'linux',
    'darwin-x64',
    'linux-ia32',
    'linux-x64',
    'win32-ia32',
    'win32-x64']

    Promise.map options.platforms, (platform) ->
      platform = 'darwin' if platform is 'osx'
      platform = 'win32' if platform is 'win'

      if platforms.indexOf(platform) < 0
        throw new PluginError PLUGIN_NAME, "Not support platform #{platform}"

      options.ext ?= "zip"
      # ex: electron-v0.24.0-darwin-x64.zip
      pkgZip = pkg = "#{packageJson.name}-#{packageJson.version}-#{platform}"
      pkgZip += '-symbols' if options.symbols
      pkgZip += ".#{options.ext}"

      cacheZip = cache = "electron-#{options.version}-#{platform}"
      cacheZip += '-symbols' if options.symbols
      cacheZip += ".#{options.ext}"
      # ex: ./cache/v0.24.0/electron-v0.24.0-darwin-x64.zip
      cachePath = path.resolve options.cache, options.version
      cacheFile = path.resolve cachePath, cacheZip
      # ex: ./cache/v0.24.0/electron-v0.24.0-darwin-x64
      cacheedPath = path.resolve cachePath, cache
      # ex: ./release/v0.24.0/
      pkgZipDir = path.join options.release, options.version
      pkgZipPath = path.resolve pkgZipDir
      pkgZipFilePath = path.resolve pkgZipDir, pkgZip
      # ex: ./release/v0.24.0/darwin-x64/
      platformDir = path.join pkgZipDir, platform
      platformPath = path.resolve platformDir

      targetApp = ""
      defaultAppName = "Electron"
      suffix = ""
      _src = path.join 'resources', 'app'
      if platform.indexOf('darwin') >= 0
        suffix = ".app"
        electronFile = "Electron" + suffix
        targetZip = options.displayName + suffix
        _src = path.join packageJson.name + suffix, 'Contents', 'Resources', 'app'
      else if platform.indexOf('win') >= 0
        suffix = ".exe"
        electronFile = "electron" + suffix
        targetZip = "."
      else
        electronFile = "electron"
        targetZip = packageJson.name #rever to name of package e.g. electron-app
      # ex: ./release/v0.24.0/darwin-x64/Electron
      electronFileDir = path.join platformDir, electronFile
      electronFilePath = path.resolve electronFileDir
      binName = options.displayName + suffix
      targetAppDir = path.join platformDir , binName
      targetAppPath = path.join targetAppDir
      _src = path.join 'resources', 'app'
      if platform.indexOf('darwin') >= 0
        _src = path.join binName, 'Contents', 'Resources', 'app'
      # ex: ./release/v0.24.0/darwin-x64/Electron/Contents/resources/app
      targetDir = path.join packageJson.name, _src
      targetDirPath = path.resolve platformDir, _src
      targetAsarPath = path.resolve platformDir, _src + ".asar"

      copyOption =
        forceDelete: true
        excludeHiddenUnix: false
        inflateSymlinks: false
      identity = ""
      if options.platformResouces?.darwin?.identity? and isFile options.platformResouces.darwin.identity
        identity = fs.readFileSync(options.platformResouces.darwin.identity, 'utf8').trim()
        ###
      signingCmd =
        # http://sevenzip.sourceforge.jp/chm/cmdline/commands/extract.htm
        darwin: [
            cmd: 'codesign'
            args: ['--deep', '--force', '--verbose', '--sign', identity, path.join(targetAppDir ,'Contents', 'Frameworks', 'Electron\\ Framework.framework')]
          ,
            cmd: 'codesign'
            args: ['--deep', '--force', '--verbose', '--sign', identity, path.join(targetAppDir ,'Contents', 'Frameworks', 'Electron\\ Helper EH.app')]
          ,
            cmd: 'codesign'
            args: ['--deep', '--force', '--verbose', '--sign', identity, path.join(targetAppDir ,'Contents', 'Frameworks', 'Electron\\ Helper NP.app')]
          ,
            cmd: 'codesign'
            args: ['--deep', '--force', '--verbose', '--sign', identity, path.join(targetAppDir ,'Contents', 'Frameworks', 'Electron\\ Helper.app')]
          ,
            cmd: 'codesign'
            args: ['--deep', '--force', '--verbose', '--sign', identity, path.join(targetAppDir ,'Contents', 'Frameworks', 'ReactiveCocoa.framework')]
          ,
            cmd: 'codesign'
            args: ['--deep', '--force', '--verbose', '--sign', identity, path.join(targetAppDir ,'Contents', 'Frameworks', 'Squirrel.framework')]
          ,
            cmd: 'codesign'
            args: ['--deep', '--force', '--verbose', '--sign', identity, path.join(targetAppDir,'Contents', 'Frameworks', 'Mantle.framework')]
          ,
            cmd: 'codesign'
            args: ['--deep', '--force', '--verbose', '--sign', identity, targetAppDir]
        ]
        ###
      unpackagingCmd =
        # http://sevenzip.sourceforge.jp/chm/cmdline/commands/extract.htm
        win32:
          cmd: '7z'
          args: ['x', cacheFile, '-o' + cacheedPath]
        darwin:
          cmd: 'unzip'
          args: ['-q', '-o', cacheFile, '-d', cacheedPath]
        linux:
          cmd: 'unzip'
          args: ['-o', cacheFile, '-d', cacheedPath]
      packagingCmd =
        # http://www.appveyor.com/docs/packaging-artifacts#packaging-multiple-files-in-different-locations-into-a-single-archive
        win32:
          cmd: '7z',
          args: ['a', path.join('..', pkgZip), targetZip],
          opts: {cwd: platformPath}
        darwin:
          cmd: 'ditto'
          args: [ '-c', '-k', '--sequesterRsrc', '--keepParent' , targetZip, path.join('..', pkgZip)]
          opts: {cwd: platformPath}
        linux:
          cmd: 'zip'
          args: ['-9', '-y', '-r', path.join('..', pkgZip) , targetZip]
          opts: {cwd: platformPath}

      new Promise (resolve,reject) ->
        Promise.resolve().then ->
          # If not downloaded then download the special package.
          download cacheFile, cachePath, options.version, cacheZip
        .then ->
          # If not unziped then unzip the zip file.
          # Check if there already have an version file.
          unzip cacheFile, cacheedPath, unpackagingCmd[process.platform]
        .then ->
          distributeBase platformPath, cacheedPath, copyOption, electronFilePath, targetAppPath
        .then ->
          if not options.rebuild
            return Promise.resolve()
          util.log PLUGIN_NAME, "Rebuilding modules"
          rebuild cmd: options.apm, args: ['rebuild']
        .then ->
          util.log PLUGIN_NAME, "distributeApp #{targetAppDir}"
          distributeApp options.src, targetDirPath, copyOption
        .then ->
          if platform.indexOf('darwin') >= 0
            #Now - PLIST updates
            util.log 'Updating Info.plist'
            plistPath = path.join targetAppPath, 'Contents', 'Info.plist'

            plistObj = plist.parse(fs.readFileSync(plistPath, 'utf8'))
            # plistObj['CFBundleDisplayName'] = plistObj['CFBundleName'] = 'Ionic Lab';
            plistObj['CFBundleDisplayName'] = plistObj['CFBundleName'] = options.displayName
            plistObj['CFBundleIdentifier'] = options.bundleId
            # fileToSave = path.join(targetAppDir, 'Info.plist')
            fs.writeFileSync(plistPath, plist.build(plistObj))
            util.log 'Finished updating plist file'
        .then ->
          if options.generateIconPath and platform.indexOf('darwin') >= 0 and process.platform.indexOf('darwin') >= 0
            iconsetFilePath = path.resolve 'resources', 'atom.iconset'
            icnsPath = path.resolve 'resources', 'atom.icns'
            fs.mkdirSync path.resolve('resources', 'atom.iconset')
            util.log 'Generating your iconset'
            iconSizes = [ 16, 32, 64, 128, 256, 512 ]

            iconSizes.forEach (iconSize) ->
              util.log iconSize
              # Example:
              # sips -z 16 16     icon.png --out ./icon_16x16.png
              # sips -z 32 32     icon.png --out ./icon_16x16@2x.png
              
              iconFileName = ['icon_', iconSize, 'x', iconSize, '.png'].join('')
              icon2xFileName = ['icon_', iconSize, 'x', iconSize, '@2x.png'].join('')
              cmd = ['sips -z', iconSize, iconSize, options.generateIconPath, '--out ', path.resolve(iconsetFilePath, iconFileName)].join(' ')
              cmd2x = ['sips -z', iconSize, iconSize, options.generateIconPath, '--out ', path.resolve(iconsetFilePath, icon2xFileName)].join(' ')

              util.log 'Running sips cmd ' + cmd
              util.log 'Running sips cmd2x ' + cmd2x

              childProcess.execSync cmd
              childProcess.execSync cmd2x

            # icons are created. Create icns file as follows:
            # iconutil -c icns ionic.iconset -o ./node-webkit/node-webkit.app/Contents/Resources/nw.icns
            iconUtilCmd = ['iconutil -c icns', iconsetFilePath, '-o', icnsPath].join(' ')

            childProcess.execSync iconUtilCmd
            options.icnsPath = icnsPath
            # cp icon.png icon_512x512@2x.png
        .then ->
          if options.icnsPath and platform.indexOf('darwin') >= 0
            util.log 'Copying Icons (icns) file ' + options.icnsPath
            # util.log 'Target app dir:' + targetAppDir
            # util.log 'Target app path: ' + targetAppPath
            readStream = fs.createReadStream options.icnsPath
            atomIcnsPath = path.join targetAppPath, 'Contents', 'Resources', 'atom.icns'
            util.log 'Copying atom.icns to: ' + atomIcnsPath
            readStream.pipe(fs.createWriteStream(atomIcnsPath))
            # plistObj['CFBundleIdentifier'] = 'com.ionic.lab';

          # else if platform.indexOf('win') >= 0 and options.iconPath
            # util.log 'Modifying exe with new icon'
            # # util.log 'Windows ' + targetAppDir
            # util.log 'Windows ' + path.resolve(targetAppPath)
            # util.log 'File path for ico ' + path.resolve(options.iconPath)
            # winresourcer({
            #   exeFile: path.resolve(targetAppPath),
            #   operation: "Update",
            #   resourceType: "ICONZ",
            #   resourceName: "IDR_MAINFRAME",
            #   resourceFile: path.resolve(options.iconPath)
            # })
        .then ->
          if not options.asar
            return Promise.resolve()
          util.log PLUGIN_NAME, "packaging app.asar"
          asarPackaging targetDirPath, targetAsarPath
        .then ->
          if not options.packaging
            return Promise.resolve()
          # FIXME: skip signing
          return Promise.resolve()
          ###
          if platform is "darwin-x64" and process.platform is "darwin"
            if identity is ""
              util.log PLUGIN_NAME, "not found identity file. skip signing"
              return Promise.resolve()
            signDarwin signingCmd.darwin
          ###
        .then ->
          if not options.packaging
            return Promise.resolve()
          packaging pkgZipFilePath, packagingCmd[process.platform]
        .then ->
          resolve()
    .finally ->
      util.log PLUGIN_NAME, "all distribute done."
      callback()

  return through.obj(bufferContents, endStream)

isDir = ->
  filepath = path.join.apply path, arguments
  fs.existsSync(filepath) and not fs.statSync(filepath).isFile()

isFile = ->
  filepath = path.join.apply path, arguments
  fs.existsSync(filepath) and fs.statSync(filepath).isFile()

isExists = ->
  filepath = path.join.apply path, arguments
  fs.existsSync(filepath)

getApmPath = ->
  apmPath = path.join 'apm', 'node_modules', 'atom-package-manager', 'bin', 'apm'
  apmPath = 'apm' unless isFile apmPath

download = (cacheFile, cachePath, version, cacheZip) ->
  if isFile cacheFile
    util.log PLUGIN_NAME, "download skip: already exists"
    return Promise.resolve()
  new Promise (resolve, reject) ->
    util.log PLUGIN_NAME, "download electron #{cacheZip} cache filie."
    wrench.mkdirSyncRecursive cachePath
    # Download electron package throw stream.
    bar = null
    grs
      repo: 'atom/electron'
      tag: version
      name: cacheZip
    .on 'error', (error) ->
      throw new PluginError PLUGIN_NAME, error
    .on 'size', (size) ->
      bar = new ProgressBar "#{cacheFile} [:bar] :percent :etas",
        complete: '>'
        incomplete: ' '
        width: 20
        total: size
    .pipe through (chunk, enc, cb) ->
      bar.tick chunk.length
      @push(chunk)
      cb()
    .pipe(fs.createWriteStream(cacheFile))
    .on 'close', resolve
    .on 'error', reject

unzip = (src, target, unpackagingCmd) ->
  if isExists target
    return Promise.resolve()
  return new Promise (resolve, reject) ->
    ###
    decompress = new Decompress src
    decompress.on 'error', reject
    decompress.on 'extract', ->
      util.log PLUGIN_NAME, "decompress done #{src}, #{target}"
      resolve()
    decompress.extract
      path: target
      follow: true
    ###
    spawn unpackagingCmd, ->
      resolve()
distributeBase = (platformPath, cacheedPath, copyOption, electronFilePath, targetAppPath) ->
  if isExists(platformPath) and isExists(targetAppPath)
    util.log PLUGIN_NAME, "distributeBase skip: already exists"
    return Promise.resolve()
  new Promise (resolve) ->
    wrench.mkdirSyncRecursive platformPath
    wrench.copyDirSyncRecursive cacheedPath, platformPath, copyOption
    mvAsync electronFilePath, targetAppPath
      .then resolve

distributeApp = (src, targetDirPath, copyOption) ->
  if isExists targetDirPath
    util.log PLUGIN_NAME, "distributeApp skip: already exists"
    return Promise.resolve()
  new Promise (resolve) ->
    rmAsync targetDirPath
      .finally ->
        wrench.mkdirSyncRecursive targetDirPath
        wrench.copyDirSyncRecursive src, targetDirPath, copyOption
        resolve()

rebuild = (cmd) ->
  new Promise (resolve) ->
    spawn cmd, resolve

asarPackaging = (src, target) ->
  util.log PLUGIN_NAME, "packaging app.asar #{src}, #{target}"
  new Promise (resolve) ->
    asar.createPackage src, target, ->
      rmAsync src
        .finally resolve

signDarwin = (signingCmd) ->
  promiseList = []
  signingCmd.forEach (cmd) ->
    p = Promise.defer()
    promiseList.push p
    spawn cmd, ->
      p.resolve()
  Promise.when promiseList

packaging = (pkgZipFilePath, packagingCmd) ->
  if not isFile pkgZipFilePath
    return new Promise (resolve) ->
      cmd = packagingCmd
      spawn cmd, ->
        resolve()
  return new Promise (resolve) ->
    rmAsync pkgZipFilePath
      .finally ->
        cmd = packagingCmd
        spawn cmd, ->
          resolve()

spawn = (options, cb) ->
  stdout = []
  stderr = []
  error = null
  options.args.forEach (arg) ->
    arg = arg.replace ' ', '\\ '
  util.log "> #{options.cmd} #{options.args.join ' '}"
  proc = childProcess.spawn options.cmd, options.args, options.opts
  proc.stdout.on 'data', (data) ->
    stdout.push data.toString()
    if process.NODE_ENV is 'test'
      util.log data.toString()
  proc.stderr.on 'data', (data) ->
    stderr.push data.toString()
  proc.on 'exit', (code, signal) ->
    error = new Error(signal) if code isnt 0
    results = stderr: stderr.join(''), stdout: stdout.join(''), code: code
    if code isnt 0
      throw new PluginError PLUGIN_NAME, results.stderr or
       'unknow error , maybe you can try delete the zip packages.'
    cb error, results
