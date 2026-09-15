interface Env {
  SUPABASE_PROJECT_REF: string
  /** Set with `wrangler secret put SUPABASE_PUBLISHABLE_KEY` — kept out of the repository. */
  SUPABASE_PUBLISHABLE_KEY: string
}

export default {
  /**
   * Runs daily. The job is deliberately a real *query* rather than a ping: Supabase counts
   * database activity, and although row-level security means this returns no rows to an
   * anonymous caller, it still executes a query against Postgres — which is the thing that
   * keeps the project off the pause list.
   *
   * There is no `fetch` handler on purpose. Nothing should be able to make this ping on
   * demand, and a cron-only Worker cannot be.
   */
  async scheduled(_event: unknown, env: Env): Promise<void> {
    const url = `https://${env.SUPABASE_PROJECT_REF}.supabase.co/rest/v1/exercises?select=id&limit=1`

    const response = await fetch(url, {
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        authorization: `Bearer ${env.SUPABASE_PUBLISHABLE_KEY}`,
      },
    })

    if (!response.ok) {
      // Throwing rather than logging quietly: a failed run should be visible in the
      // Worker's own metrics, because the whole point is that nobody is watching.
      throw new Error(`keep-alive failed: ${response.status} ${await response.text()}`)
    }

    console.log(`keep-alive ok (${response.status})`)
  },
}
