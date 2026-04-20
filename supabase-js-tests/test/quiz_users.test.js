import test from 'node:test'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

function getEnv(name) {
  const value = process.env[name]
  if (!value) throw new Error(`Missing env var: ${name}`)
  return value
}

function createServiceClient() {
  const url = getEnv('SUPABASE_URL')
  const serviceKey = getEnv('SUPABASE_SERVICE_ROLE_KEY')
  return createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

test('quiz_users: insert returns id, name, score', async () => {
  const supabase = createServiceClient()

  const id = randomUUID()
  const name = `test_${id.slice(0, 8)}`

  await supabase.from('quiz_users').delete().eq('id', id)

  const { data, error } = await supabase
    .from('quiz_users')
    .insert({ id, name, image: null })
    .select('id, name, score')
    .single()

  assert.equal(error, null)
  assert.equal(data.id, id)
  assert.equal(data.name, name)
  assert.equal(data.score, 0)
})

test('quiz_users: leaderboard is sorted by score desc', async () => {
  const supabase = createServiceClient()

  const rows = Array.from({ length: 8 }, (_, i) => ({
    id: randomUUID(),
    name: `lb_${i}`,
    image: null,
    score: i % 2 === 0 ? 100 - i : i,
  }))

  const ids = rows.map((r) => r.id)
  await supabase.from('quiz_users').delete().in('id', ids)

  const { error: insertError } = await supabase.from('quiz_users').insert(rows)
  assert.equal(insertError, null)

  const { data, error } = await supabase
    .from('quiz_users')
    .select('id, score')
    .in('id', ids)
    .order('score', { ascending: false })
    .order('id', { ascending: true })

  assert.equal(error, null)

  for (let i = 1; i < data.length; i++) {
    assert.ok(data[i - 1].score >= data[i].score)
  }
})
