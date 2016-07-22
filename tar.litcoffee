#Tar parser

Block size is 512 bytes

    BLOCK = 512
    ZLIB = null
    if module?
     try
      ZLIB = require 'zlib'
     catch e
      ZLIB = null


Node Buffer

    class NodeTarBuffer
     constructor: (length) ->
      @buffer = new Buffer length
      for i in [0...@buffer.length]
       @buffer[i] = 0

      @writeOffset = 0

     write: (str, len) ->
      len ?= str.length
      if str.length > len
       throw new Error "String doesnt fit the header: #{str}, #{len}"
      @buffer.write str, @writeOffset, str.length, 'ascii'
      @writeOffset += len

     checksum: ->
      checksum = 0
      for i in [0...@buffer.length]
       checksum += @buffer[i]

      return checksum

     copy: (buffer, offset) ->
      buffer.copy @buffer, offset, 0



Typed tar buffer


    class TypedTarBuffer
     constructor: (length) ->
      @buffer = new Uint8Array length
      @writeOffset = 0

     write: (str, len) ->
      len ?= str.length
      if str.length > len
       throw new Error "String doesnt fit the header: #{str}, #{len}"
      for i in [0...str.length]
       @buffer[@writeOffset + i] = str.charCodeAt i
      @writeOffset += len

     checksum: ->
      checksum = 0
      for i in [0...@buffer.length]
       checksum += @buffer[i]

      return checksum

     copy: (buffer, offset) ->
      for i in [0...buffer.length]
       @buffer[offset + i] = buffer[i]



    if window?.document?.removeEventListener?
     TarBuffer = TypedTarBuffer
    else
     TarBuffer = NodeTarBuffer


Tar class



    class Tar

     constructor: (encoding = 'utf8') ->
      @data = null
      @files = {}
      @encoding = 'utf8'

     _prefixFill: (s, length, fill = '0') ->
       while s.length < length
        s = fill + s
       return s

     _joinPath: (path, prefix) ->
      if path? then "#{prefix}/#{path}" else prefix


     _createHeader: (file) ->
      header =
       filename: file.filename
       mode: @_prefixFill ((file.mode & 0o777).toString 8), 7
       uid: @_prefixFill (file.uid.toString 8), 7
       gid: @_prefixFill (file.gid.toString 8), 7
       length: @_prefixFill (file.content.length.toString 8), 11
       lastModified: (file.lastModified.getTime() // 1000).toString 8
       checkSum: 0
       fileType: if file.directory then '5' else '0'
       linkName: ''
       longFilename: {}
       owner:
        name: 'varuna'
        group: 'varuna'
       device:
        major: ''
        minor: ''

      if file.directory
       header.filename += '/'

      header.longFilename =
       name: header.filename
       prefix: ''
      if header.filename.length > 100
       long = header.longFilename =
        name: null
        prefix: null
       parts = header.filename.split '/'

       while parts.length > 0
        temp = @_joinPath long.name, parts[parts.length - 1]
        break if temp.length > 100
        long.name = temp
        parts.pop()
       while parts.length > 0
        temp = @_joinPath long.prefix, parts[parts.length - 1]
        long.prefix = temp
        parts.pop()

       long.name ?= ''
       long.prefix ?= ''

      return header


     create: (files) ->
      @files = files
      headers = {}
      nBlocks = 0

      list = (path for path of @files)
      list.sort()

      for path in list
       file = @files[path]
       header = @_createHeader file

       headerBuffer = new TarBuffer 512

       headerBuffer.write header.longFilename.name, 100
       headerBuffer.write header.mode, 8
       headerBuffer.write header.uid, 8
       headerBuffer.write header.gid, 8
       headerBuffer.write header.length, 12
       headerBuffer.write header.lastModified, 12
       checksumOffset = headerBuffer.writeOffset
       headerBuffer.write '        ', 8
       headerBuffer.write header.fileType, 1
       headerBuffer.write header.linkName, 100
       headerBuffer.write 'ustar', 6
       headerBuffer.write '00', 2
       headerBuffer.write header.owner.name, 32
       headerBuffer.write header.owner.group, 32
       headerBuffer.write header.device.major, 8
       headerBuffer.write header.device.minor, 8
       headerBuffer.write header.longFilename.prefix, 155


       checksum = headerBuffer.checksum()
       header.checksum = @_prefixFill (checksum.toString 8), 6
       headerBuffer.writeOffset = checksumOffset
       headerBuffer.write header.checksum, 6

       #NUL and space
       headerBuffer.writeOffset++
       headerBuffer.write ' ', 1

       headers[path] = headerBuffer.buffer
       nBlocks += 1 + Math.ceil file.content.length / BLOCK

      @data = new TarBuffer nBlocks * BLOCK

      n = 0
      for path in list
       file = @files[path]
       @data.copy headers[path], n
       n += BLOCK
       @data.copy file.content, n
       n += BLOCK * Math.ceil file.content.length / BLOCK

      @data = @data.buffer


     gzip: (data, callback) ->
      if not ZLIB?
       throw Error 'zlib not present'
      ZLIB.gzip data, callback

     gunzip: (data, callback) ->
      if not ZLIB?
       throw Error 'zlib not present'
      ZLIB.gunzip data, callback

     parse: (data, gzip = false) ->
      @data = data

      if @data.byteLength?
       L = @data.byteLength
      else
       L = @data.length

      n = 0
      while n + BLOCK <= L
       file = @_parseHeader n
       if file.length > 0 or file.filename isnt ''
        n += BLOCK
        if n + file.length > L
         throw new Error 'Error parsing tar file'
        file.content = @data.slice n, n + file.length
        @files[file.filename] = file
        n += BLOCK * Math.ceil file.length / BLOCK
       else
        break

     _bufferToString: (buffer) ->

If it is an ArrayBuffer

      if buffer.byteLength?
       return String.fromCharCode.apply null, new Uint8Array buffer

If it is NodeJS Buffer

      else
       return buffer.toString 'ascii'

     _parseHeader: (n) ->
      header = {}

      sub = (l) =>
       s = @_bufferToString @data.slice n, n + l
       n += l
       s = s.split "\0", 1
       return s[0]

      len = (l) =>
       s = @_bufferToString @data.slice n, n + l
       n += l
       return parseInt (s.replace /[^\d]/g, ''), 8

      header.longFilename = {}
      header.longFilename.name = sub 100
      header.mode = sub 8
      header.uid = sub 8
      header.gid = sub 8
      header.length = len 12
      header.lastModified = sub 12
      header.checkSum = sub 8
      header.fileType = sub 1
      header.linkName = sub 100
      header.ustar = sub 6
      header.ustarVersion = sub 2
      header.owner = {}
      header.owner.name = sub 32
      header.owner.group = sub 32
      header.device = {}
      header.device.major = sub 8
      header.device.minor = sub 8
      header.longFilename.prefix = sub 155
      if header.longFilename.prefix isnt ''
       header.filename = "#{header.longFilename.prefix}/#{header.longFilename.name}"
      else
       header.filename = header.longFilename.name


      return header




#Exports

    if module?
     module.exports = Tar

    if window?
     @Tar = Tar
