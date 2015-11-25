#Tar parser

Block size is 512 bytes

    BLOCK = 512
    ZLIB = null
    if module?
     try
      ZLIB = require 'zlib'
     catch e
      ZLIB = null


    class Tar

     constructor: (encoding = 'utf8') ->
      @data = null
      @files = {}
      @encoding = 'utf8'

     create: (files) ->
      @files = files
      headers = {}
      nBlocks = 0

      prefix = (s, length, fill = '0') ->
       while s.length < length
        s = fill + s
       return s

      list = (path for path of @files)
      list.sort()

      for path in list
       file = @files[path]
       header =
        filename: file.filename
        mode: prefix ((file.mode & 0o777).toString 8), 7
        uid: prefix (file.uid.toString 8), 7
        gid: prefix (file.gid.toString 8), 7
        length: prefix (file.content.length.toString 8), 11
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
         name: ''
         prefix: ''
        parts = header.filename.split '/'

        joinPath = (path, prefix) ->
         temp = path
         temp = "/#{temp}" if temp.length > 0
         temp = "#{prefix}#{temp}"
         return temp

        while parts.length > 0
         temp = joinPath long.name, parts[parts.length - 1]
         if long.name is '' and file.directory
          temp = "#{temp}/"
         break if temp.length > 100
         long.name = temp
         parts.pop()
        while parts.length > 0
         temp = joinPath long.prefix, parts[parts.length - 1]
         if long.name is '' and long.prefix is '' and file.directory
          temp = "#{temp}/"
         long.prefix = temp
         parts.pop()

       headerBuffer = new Buffer 512
       for i in [0...512]
        headerBuffer[i] = 0

       n = 0
       writeToBuffer = (str, len) ->
        len ?= str.length
        if str.length > len
         throw new Error "String doesnt fit the header: #{str}, #{len}"
        headerBuffer.write str, n, str.length, 'ascii'
        n += len

       n = 0
       writeToBuffer header.longFilename.name, 100
       writeToBuffer header.mode, 8
       writeToBuffer header.uid, 8
       writeToBuffer header.gid, 8
       writeToBuffer header.length, 12
       writeToBuffer header.lastModified, 12
       checksumOffset = n
       writeToBuffer '        ', 8
       writeToBuffer header.fileType, 1
       writeToBuffer header.linkName, 100
       writeToBuffer 'ustar', 6
       writeToBuffer '00', 2
       writeToBuffer header.owner.name, 32
       writeToBuffer header.owner.group, 32
       writeToBuffer header.device.major, 8
       writeToBuffer header.device.minor, 8
       writeToBuffer header.longFilename.prefix, 155


       checksum = 0
       for i in [0...512]
        checksum += headerBuffer[i]

       header.checksum = prefix (checksum.toString 8), 6
       n = checksumOffset
       headerBuffer.write header.checksum, n, 6, 'ascii'
       n += 7
       headerBuffer.write ' ', n, 1, 'ascii'

       headers[path] = headerBuffer
       nBlocks += 1 + Math.ceil file.content.length / BLOCK

      @data = new Buffer nBlocks * BLOCK

      for i in [0...@data.length]
       @data[i] = 0

      n = 0
      for path in list
       file = @files[path]
       headers[path].copy @data, n, 0
       n += BLOCK
       file.content.copy @data, n, 0
       n += BLOCK * Math.ceil file.content.length / BLOCK

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
      while n + BLOCK < L
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
