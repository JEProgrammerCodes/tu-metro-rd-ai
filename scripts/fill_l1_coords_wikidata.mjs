import fs from 'node:fs/promises'
import path from 'node:path'

const stations = [
  {
    code: 'L1-01',
    name: 'Mamá Tingó',
    queries: [
      'Mamá Tingó (Santo Domingo Metro)',
      'Estación Mamá Tingó (Metro de Santo Domingo)',
      'Mamá Tingó metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-02',
    name: 'Gregorio Urbano Gilbert',
    queries: [
      'Gregorio Urbano Gilbert (Santo Domingo Metro)',
      'Gregorio U. Gilbert (Metro de Santo Domingo)',
      'Gregorio Urbano Gilbert metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-03',
    name: 'Gregorio Luperón',
    queries: [
      'Gregorio Luperón (Santo Domingo Metro)',
      'Estación Gregorio Luperón (Metro de Santo Domingo)',
      'Gregorio Luperón metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-04',
    name: 'José Francisco Peña Gómez',
    queries: [
      'José Francisco Peña Gómez (Santo Domingo Metro)',
      'Estación José Francisco Peña Gómez (Metro de Santo Domingo)',
      'José Francisco Peña Gómez metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-05',
    name: 'Hermanas Mirabal',
    queries: [
      'Hermanas Mirabal (Santo Domingo Metro)',
      'Estación Hermanas Mirabal (Metro Santo Domingo)',
      'Hermanas Mirabal metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-06',
    name: 'Máximo Gómez',
    queries: [
      'Máximo Gómez (Santo Domingo Metro)',
      'Estación Máximo Gómez (Metro De Santo Domingo)',
      'Máximo Gómez metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-07',
    name: 'Los Taínos',
    queries: [
      'Los Taínos (Santo Domingo Metro)',
      'Estación Los Taínos (Metro de Santo Domingo)',
      'Los Taínos metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-08',
    name: 'Pedro Livio Cedeño',
    queries: [
      'Pedro Livio Cedeño (Santo Domingo Metro)',
      'Estación Pedro Livio Cedeño (Metro de Santo Domingo)',
      'Pedro Livio Cedeño metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-09',
    name: 'Manuel Arturo Peña Batlle',
    queries: [
      'Manuel Arturo Peña Batlle (Santo Domingo Metro)',
      'Estación Manuel Arturo Peña Batlle (Metro de Santo Domingo)',
      'Manuel Arturo Peña Batlle metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-10',
    name: 'Juan Pablo Duarte',
    queries: [
      'Juan Pablo Duarte (estación del Metro de Santo Domingo)',
      'Juan Pablo Duarte (Santo Domingo Metro)',
      'Juan Pablo Duarte metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-11',
    name: 'Prof. Juan Bosch',
    queries: [
      'Juan Bosch (Santo Domingo Metro)',
      'Profesor Juan Bosch (Metro de Santo Domingo)',
      'Juan Bosch metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-12',
    name: 'Casandra Damirón',
    queries: [
      'Casandra Damirón (Santo Domingo Metro)',
      'Estación Casandra Damirón (Metro de Santo Domingo)',
      'Casandra Damirón metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-13',
    name: 'Dr. Joaquín Balaguer',
    queries: [
      'Joaquín Balaguer (Santo Domingo Metro)',
      'Dr. Joaquín Balaguer (Metro de Santo Domingo)',
      'Joaquín Balaguer metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-14',
    name: 'Amín Abel Hasbún',
    queries: [
      'Amín Abel (Santo Domingo Metro)',
      'Amín Abel Hasbún (Metro de Santo Domingo)',
      'Amín Abel metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-15',
    name: 'Francisco Alberto Caamaño Deñó',
    queries: [
      'Francisco Alberto Caamaño (Santo Domingo Metro)',
      'Francisco Alberto Caamaño Deñó (Metro de Santo Domingo)',
      'Francisco Alberto Caamaño metro station Santo Domingo',
    ],
  },
  {
    code: 'L1-16',
    name: 'Centro de los Héroes',
    queries: [
      'Centro de los Héroes (Santo Domingo Metro)',
      'Centro de los Héroes (estación del Metro de Santo Domingo)',
      'Centro de los Héroes metro station Santo Domingo',
    ],
  },
]

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function csvEscape(value) {
  const s = String(value ?? '')
  if (s.includes(',') || s.includes('"') || s.includes('\n')) {
    return `"${s.replace(/"/g, '""')}"`
  }
  return s
}

function extractCoordinates(entity) {
  const p625 = entity?.claims?.P625?.[0]?.mainsnak?.datavalue?.value
  if (!p625) return null
  return {
    lat: Number(p625.latitude),
    lon: Number(p625.longitude),
  }
}

function scoreResult(result) {
  const text = `${result.label ?? ''} ${result.description ?? ''}`.toLowerCase()
  let score = 0
  if (text.includes('santo domingo')) score += 5
  if (text.includes('metro')) score += 5
  if (text.includes('station')) score += 2
  if (text.includes('estación')) score += 2
  return score
}

async function searchEntity(query) {
  const url =
    `https://www.wikidata.org/w/api.php?action=wbsearchentities&format=json` +
    `&language=es&uselang=es&type=item&limit=8&search=${encodeURIComponent(query)}&origin=*`

  const res = await fetch(url)
  if (!res.ok) {
    throw new Error(`wbsearchentities falló con ${res.status}`)
  }

  const data = await res.json()
  const results = Array.isArray(data.search) ? data.search : []
  return results.sort((a, b) => scoreResult(b) - scoreResult(a))
}

async function getEntity(entityId) {
  const url =
    `https://www.wikidata.org/w/api.php?action=wbgetentities&format=json` +
    `&ids=${encodeURIComponent(entityId)}&languages=es|en&props=labels|claims&origin=*`

  const res = await fetch(url)
  if (!res.ok) {
    throw new Error(`wbgetentities falló con ${res.status}`)
  }

  const data = await res.json()
  return data.entities?.[entityId] ?? null
}

async function resolveStation(station) {
  for (const query of station.queries) {
    const searchResults = await searchEntity(query)

    for (const result of searchResults) {
      const entity = await getEntity(result.id)
      const coords = extractCoordinates(entity)
      if (!coords) continue

      const labelEs = entity?.labels?.es?.value ?? ''
      const labelEn = entity?.labels?.en?.value ?? ''
      const description =
        result.description ??
        entity?.descriptions?.es?.value ??
        entity?.descriptions?.en?.value ??
        ''

      const text = `${labelEs} ${labelEn} ${description}`.toLowerCase()

      if (!text.includes('santo domingo') && !text.includes('metro')) {
        continue
      }

      return {
        code: station.code,
        name: station.name,
        lat: coords.lat,
        lon: coords.lon,
        source: 'Wikidata',
        sourceUrl: `https://www.wikidata.org/wiki/${result.id}`,
        note: `Coincidencia: ${labelEs || labelEn || result.id}`,
      }
    }

    await sleep(200)
  }

  return {
    code: station.code,
    name: station.name,
    lat: '',
    lon: '',
    source: 'Wikidata',
    sourceUrl: '',
    note: 'No resuelto automáticamente',
  }
}

async function main() {
  const outRows = [
    ['estacion_codigo', 'nombre', 'lat', 'lon', 'fuente', 'fuente_url', 'observaciones'],
  ]

  const unresolved = []

  for (const station of stations) {
    console.log(`Buscando: ${station.code} - ${station.name}`)
    const row = await resolveStation(station)

    if (row.lat === '' || row.lon === '') {
      unresolved.push(`${station.code} - ${station.name}`)
    }

    outRows.push([
      row.code,
      row.name,
      row.lat,
      row.lon,
      row.source,
      row.sourceUrl,
      row.note,
    ])

    await sleep(250)
  }

  const csv = outRows.map((r) => r.map(csvEscape).join(',')).join('\n') + '\n'

  const outPath = path.resolve('data', 'import_estaciones_l1_coordenadas.csv')
  await fs.writeFile(outPath, csv, 'utf8')

  console.log('\nArchivo generado:')
  console.log(outPath)

  if (unresolved.length) {
    console.log('\nNo resueltas automáticamente:')
    for (const item of unresolved) console.log(`- ${item}`)
    process.exitCode = 2
  } else {
    console.log('\nTodas las estaciones fueron resueltas.')
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})