-- imita o mínimo do Supabase
create role authenticated; create role anon;
create schema auth; create table auth.users (id uuid primary key default gen_random_uuid());
create schema storage;
create table storage.buckets (id text primary key, name text, public boolean);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text);
alter table storage.objects enable row level security;
