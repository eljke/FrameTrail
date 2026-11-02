begin;
do $setup$
declare owner_id uuid;
begin
    select id into strict owner_id from auth.users where email_confirmed_at is not null order by created_at limit 1;
    perform set_config('request.jwt.claim.sub', owner_id::text, true);
end $setup$;
set local role authenticated;
do $test$
declare
    item jsonb := '{"title":{"id":"validation:preferences"},"progress":{},"reflections":[],"nameAliases":[{"original":"Walter","russian":"Уолтер"}],"recommendationHidden":true,"recommendationWasSaved":true}'::jsonb;
    received jsonb;
begin
    select payload into strict received from public.put_library_item('validation:preferences', item, 0, false);
    if received is distinct from item then raise exception 'Metadata did not round trip'; end if;
    begin
        perform public.put_library_item('validation:preferences', item || '{"unknown":true}'::jsonb, 1, false);
        raise exception 'Unknown metadata was accepted';
    exception when sqlstate '22023' then null;
    end;
    begin
        perform public.put_library_item('validation:preferences', item || '{"recommendationHidden":"true"}'::jsonb, 1, false);
        raise exception 'Invalid preference type was accepted';
    exception when sqlstate '22023' then null;
    end;
    if exists(select 1 from public.put_library_item('validation:preferences', item, 9, false)) then
        raise exception 'Stale revision was accepted';
    end if;
end $test$;
rollback;
