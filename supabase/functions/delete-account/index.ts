const json = (status: number, error: string) => Response.json({ error }, { status });

Deno.serve(async (request: Request) => {
  if (request.method !== "DELETE") return json(405, "Method not allowed");
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json(401, "Authentication required");
  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  try {
    const identity = await fetch(`${url}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: authorization },
      signal: AbortSignal.timeout(10000),
    });
    if (!identity.ok) return json(401, "Authentication required");
    const user = await identity.json();
    if (typeof user.id !== "string" || !/^[0-9a-f-]{36}$/i.test(user.id)) {
      return json(401, "Authentication required");
    }
    const deletion = await fetch(`${url}/auth/v1/admin/users/${user.id}`, {
      method: "DELETE",
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
      signal: AbortSignal.timeout(10000),
    });
    if (!deletion.ok) return json(502, "Account deletion failed");
    return new Response(null, { status: 204 });
  } catch {
    return json(503, "Account service unavailable");
  }
});
