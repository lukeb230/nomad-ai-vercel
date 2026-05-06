-- supabase/migrations/20260427_campsites.sql
-- Adds the campsites table backing DB-first search, plus a Postgres function
-- for radius queries that the new search-campsites Edge Function will call.

create table if not exists public.campsites (
    id uuid primary key default gen_random_uuid(),
    -- Stable upstream id, e.g. "ridb:facility:12345". Used for upserts on refresh.
    external_id text not null unique,
    -- 'ridb' for now; future: 'osm', 'iov', etc.
    source text not null default 'ridb',
    name text not null,
    description text,
    lat double precision not null,
    lng double precision not null,
    phone text,
    email text,
    reservation_url text,
    reservable boolean default false,
    facility_type text,
    -- USFS / NPS / BLM / USACE / FWS / BOR / etc. Pulled from OrgRecAreaID joins
    -- when available, else inferred from the parent recarea name.
    agency text,
    last_updated timestamptz,
    -- Raw RIDB record. Lets us promote new fields later without re-ingesting.
    raw jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists campsites_lat_lng_idx on public.campsites (lat, lng);
create index if not exists campsites_source_idx  on public.campsites (source);

-- RLS: anon can SELECT (read-only public data); only service role can write.
alter table public.campsites enable row level security;

drop policy if exists "campsites: anon read" on public.campsites;
create policy "campsites: anon read"
    on public.campsites
    for select
    using (true);

-- No INSERT/UPDATE/DELETE policies for anon. Service role bypasses RLS, so
-- the local ingest script can write freely.

-- Bounding-box prefilter then haversine distance. ~5K-10K rows total, so
-- index-backed bbox + sequential haversine on the filtered slice is fast.
create or replace function public.search_campsites_nearby(
    p_lat double precision,
    p_lng double precision,
    p_radius_miles double precision,
    p_limit int default 20
)
returns table (
    id uuid,
    external_id text,
    source text,
    name text,
    description text,
    lat double precision,
    lng double precision,
    reservation_url text,
    reservable boolean,
    facility_type text,
    agency text,
    distance_miles double precision
)
language sql
stable
as $$
    with prefiltered as (
        select c.*,
            3958.8 * 2 * asin(
                sqrt(
                    pow(sin(radians((c.lat - p_lat) / 2)), 2) +
                    cos(radians(p_lat)) * cos(radians(c.lat)) *
                    pow(sin(radians((c.lng - p_lng) / 2)), 2)
                )
            ) as distance_miles
        from public.campsites c
        where c.lat between p_lat - (p_radius_miles / 69.0) and p_lat + (p_radius_miles / 69.0)
          and c.lng between p_lng - (p_radius_miles / greatest(1.0, 69.0 * cos(radians(p_lat))))
                       and p_lng + (p_radius_miles / greatest(1.0, 69.0 * cos(radians(p_lat))))
    )
    select
        id, external_id, source, name, description, lat, lng,
        reservation_url, reservable, facility_type, agency, distance_miles
    from prefiltered
    where distance_miles <= p_radius_miles
    order by distance_miles asc
    limit p_limit;
$$;
