export interface SurveyPacket {
  ply: string
  plyName: string
  survey?: unknown
  surveyName?: string
}

const decoder = new TextDecoder()

function fail(message: string): never {
  throw new Error(`${message} Unzip the packet and drop scene.ply with survey.json instead.`)
}

function findEndOfCentralDirectory(bytes: Uint8Array): number {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  const first = Math.max(0, bytes.length - 65_557)
  for (let offset = bytes.length - 22; offset >= first; offset--) {
    if (view.getUint32(offset, true) === 0x06054b50) return offset
  }
  return fail("This ZIP packet is malformed or incomplete.")
}

async function inflateRaw(bytes: Uint8Array): Promise<Uint8Array> {
  try {
    const copy = Uint8Array.from(bytes)
    const stream = new Blob([copy.buffer]).stream().pipeThrough(new DecompressionStream("deflate-raw"))
    return new Uint8Array(await new Response(stream).arrayBuffer())
  } catch {
    return fail("This browser cannot decompress the survey ZIP locally.")
  }
}

async function extractEntry(bytes: Uint8Array, offset: number, compressedSize: number, expectedSize: number, method: number) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  if (offset + 30 > bytes.length || view.getUint32(offset, true) !== 0x04034b50) fail("The ZIP contains an invalid file entry.")
  const nameLength = view.getUint16(offset + 26, true)
  const extraLength = view.getUint16(offset + 28, true)
  const start = offset + 30 + nameLength + extraLength
  const end = start + compressedSize
  if (end > bytes.length) fail("The ZIP contains a truncated file entry.")
  const compressed = bytes.slice(start, end)
  const output = method === 0 ? compressed : method === 8 ? await inflateRaw(compressed) : fail(`ZIP compression method ${method} is not supported.`)
  if (expectedSize !== output.length) fail("A file in the ZIP did not decompress to its expected size.")
  return output
}

/** Reads only scene.ply and survey.json. Photos, depth, and other packet files stay untouched. */
export async function readSurveyPacket(file: File): Promise<SurveyPacket> {
  const bytes = new Uint8Array(await file.arrayBuffer())
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  const end = findEndOfCentralDirectory(bytes)
  const disk = view.getUint16(end + 4, true)
  const centralDisk = view.getUint16(end + 6, true)
  const entries = view.getUint16(end + 10, true)
  const centralSize = view.getUint32(end + 12, true)
  const centralOffset = view.getUint32(end + 16, true)
  if (disk !== 0 || centralDisk !== 0) fail("Multi-part ZIP packets are not supported.")
  if (entries === 0xffff || centralSize === 0xffffffff || centralOffset === 0xffffffff) fail("ZIP64 packets are not supported.")
  if (centralOffset + centralSize > bytes.length) fail("The ZIP central directory is invalid.")

  let offset = centralOffset
  const wanted = new Map<string, { name: string; flags: number; method: number; compressed: number; size: number; local: number }>()
  for (let index = 0; index < entries; index++) {
    if (offset + 46 > bytes.length || view.getUint32(offset, true) !== 0x02014b50) fail("The ZIP central directory is malformed.")
    const flags = view.getUint16(offset + 8, true)
    const method = view.getUint16(offset + 10, true)
    const compressed = view.getUint32(offset + 20, true)
    const size = view.getUint32(offset + 24, true)
    const nameLength = view.getUint16(offset + 28, true)
    const extraLength = view.getUint16(offset + 30, true)
    const commentLength = view.getUint16(offset + 32, true)
    const local = view.getUint32(offset + 42, true)
    const nameStart = offset + 46
    const name = decoder.decode(bytes.slice(nameStart, nameStart + nameLength))
    const base = name.split("/").filter(Boolean).pop()?.toLowerCase()
    if (base === "scene.ply" || base === "survey.json") {
      if (flags & 1) fail("Encrypted ZIP packets are not supported.")
      wanted.set(base, { name, flags, method, compressed, size, local })
    }
    offset = nameStart + nameLength + extraLength + commentLength
  }

  const scene = wanted.get("scene.ply")
  if (!scene) fail("This packet does not contain scene.ply.")
  const ply = decoder.decode(await extractEntry(bytes, scene.local, scene.compressed, scene.size, scene.method))
  const packet: SurveyPacket = { ply, plyName: scene.name }
  const survey = wanted.get("survey.json")
  if (survey) {
    const text = decoder.decode(await extractEntry(bytes, survey.local, survey.compressed, survey.size, survey.method))
    try {
      packet.survey = JSON.parse(text)
      packet.surveyName = survey.name
    } catch {
      fail("survey.json inside the ZIP is not valid JSON.")
    }
  }
  return packet
}
