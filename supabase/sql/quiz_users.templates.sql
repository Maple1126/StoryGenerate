insert into public.quiz_users (id, name, image)
values ($1::uuid, $2::text, $3::text)
returning id, name, image, score, rank;

update public.quiz_users
set score = score + 1
where id = $1::uuid
returning id, score, rank;
