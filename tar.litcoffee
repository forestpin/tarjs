#Tar parser

Block size is 512 bytes

    BLOCK = 512


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

      for path, file of @files
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

       if file.directory
        header.filename += '/'

       headerBuffer = new Buffer 512
       for i in [0...512]
        headerBuffer[i] = 0

       n = 0
       filename = header.filename
       filenamePrefix = ''
       if header.filename.length > 100
        filename = header.filename.substr header.filename.length - 100
        filenamePrefix = header.filename.substr 0, header.filename.length - 100
       headerBuffer.write filename, n, filename.length, 'ascii'
       n += 100
       headerBuffer.write header.mode, n, 7, 'ascii'
       n += 8
       headerBuffer.write header.uid, n, 7, 'ascii'
       n += 8
       headerBuffer.write header.gid, n, 7, 'ascii'
       n += 8
       headerBuffer.write header.length, n, 11, 'ascii'
       n += 12
       headerBuffer.write header.lastModified, n, 11, 'ascii'
       n += 12
       checksumOffset = n
       headerBuffer.write '        ', n, 8, 'ascii'
       n += 8
       headerBuffer.write header.fileType, n, 1, 'ascii'
       n += 1
       headerBuffer.write header.linkName, n, header.linkName.length, 'ascii'
       if filenamePrefix?
        console.log 'prefix'
        n = 345
        if filenamePrefix.length > 155
         throw new Error "Filename too long: #{header.filename}"
        headerBuffer.write filenamePrefix, n, filenamePrefix.length, 'ascii'


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
      for path, file of @files
       headers[path].copy @data, n, 0
       n += BLOCK
       file.content.copy @data, n, 0
       n += BLOCK * Math.ceil file.content.length / BLOCK

     parse: (data) ->
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

      header.filename = sub 100
      header.mode = sub 8
      header.uid = sub 8
      header.gid = sub 8
      header.length = len 12
      header.lastModified = sub 12
      header.checkSum = sub 8
      header.fileType = sub 1
      header.linkName = sub 100

      return header




#Exports

    if module?
     module.exports = Tar

    if window?
     @Tar = Tar
