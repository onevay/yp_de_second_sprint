--создаем таблицу со стоимостью комиссии по разным странам (уникальные значения для разных товаров)
create table if not exists public.shipping_country_rates(
id serial,
shipping_country text,
shipping_country_price bigint,
primary key (id));

insert
	into
	public.shipping_country_rates (shipping_country,
	shipping_country_price)
select
	distinct s.shipping_country,
	round(s.shipping_country_base_rate * s.payment)
from
	public.shipping s
where
	not exists(
	select
		1
	from
		public.shipping_country_rates
	where
		s.shipping_country = shipping_country
		and round(s.shipping_country_base_rate * s.payment) = shipping_country_price);

--создаем и заполняем таблицу с информацией о поставщиках
create table if not exists public.shipping_agreement(
agreementid bigint,
agreement_number bigint,
agreement_rate decimal(3,
2),
agreement_commission decimal(3,
2),
primary key(agreementid));
with agreement_tmp as(
select distinct
	string_to_array(vendor_agreement_description,
	':') sta
from
	public.shipping s)
insert
	into
	public.shipping_agreement(agreementid,
	agreement_number,
	agreement_rate,
	agreement_commission)
(
	select
		cast(sta[1] as bigint),
		cast(array_to_string(regexp_match(sta[2],
		'[0-9]+'), '') as bigint),
		cast(sta[3] as decimal(3,
		2)),
		cast(sta[4] as decimal(3,
		2))
	from
		agreement_tmp) on
	conflict(agreementid) do
update
set
	agreement_number = excluded.agreement_number ;

--создаем и заполняем таблицу с информацией о типе доставки
create table if not exists public.shipping_transfer(
id serial,
transfer_type varchar(5),
transfer_model text,
shipping_transfer_rate decimal(8,
8),
primary key(id));

with transfer_tmp as(
select
	distinct
	string_to_array(s.shipping_transfer_description,
	':') sta,
	s.shipping_transfer_rate
from
	public.shipping s )
insert
	into
	public.shipping_transfer(transfer_type,
	transfer_model,
	shipping_transfer_rate)
select
	sta[1],
	sta[2],
	shipping_transfer_rate
from
	transfer_tmp tt
where
	not exists(
	select
		1
	from
		shipping_transfer st
	where
		st.transfer_type = tt.sta[1]
		and st.transfer_model = tt.sta[2]
		and st.shipping_transfer_rate = tt.shipping_transfer_rate);

--создание таблицы-связи
create table if not exists shipping_info(
shippingid serial,
shipping_country_rates_id bigint,
shipping_agreement_id bigint,
shipping_transfer_id bigint,
shipping_plan_datetime timestamp,
payment_amount bigint,
vendorid bigint,
primary key (shippingid),
foreign key(shipping_country_rates_id) references shipping_country_rates(id) on delete cascade,
foreign key(shipping_agreement_id) references shipping_agreement(agreementid) on delete cascade,
foreign key(shipping_transfer_id) references shipping_transfer(id));

with shipping_tmp as(
select
	distinct s.shipping_id,
	scr.id,
	a.agreementid,
	t.id,
	s.shipping_plan_datetime,
	s.payment,
	s.vendor_id
from
	public.shipping s
left join public.shipping_agreement a on
	concat(a.agreementid::text,
	':',
	'vspn-',
	a.agreement_number::text,
	':',
	a.agreement_rate::text,
	':',
	a.agreement_commission::text) = s.vendor_agreement_description
left join public.shipping_country_rates scr on
	scr.shipping_country = s.shipping_country
	and scr.shipping_country_price = round(s.shipping_country_base_rate * s.payment)
left join public.shipping_transfer t on
	concat(t.transfer_type::text,
	':',
	t.transfer_model::text) = s.shipping_transfer_description
	and t.shipping_transfer_rate = s.shipping_transfer_rate )
insert
	into
	public.shipping_info(shippingid,
	shipping_country_rates_id,
	shipping_agreement_id,
	shipping_transfer_id,
	shipping_plan_datetime,
	payment_amount,
	vendorid)
select
	*
from
	shipping_tmp st on
	conflict(shippingid) do update set shipping_country_rates_id = excluded.shipping_country_rates_id;

--создаем и заполняем таблицу для отслеживания статусов доставок
create table if not exists shipping_status (
shipping_id bigint,
status text,
state text,
shipping_start_fact_datetime timestamp,
shipping_end_fact_datetime timestamp,
primary key(shipping_id));

with status_tmp as(
select
	distinct
	shipping_id,
	last_value(status) over(partition by shipping_id
order by
	state_datetime) as last_status,
	last_value(state) over(partition by shipping_id
order by
	state_datetime) as last_state
from
	public.shipping s),
times_tmp as(
select
	distinct shipping_id,
	first_value(state_datetime) over(partition by shipping_id
order by
	state_datetime) as first_date,
	last_value(state_datetime) over(partition by shipping_id
order by
	state_datetime) as last_date
from
	public.shipping s
where
	state like 'booked'
	or state like 'recieved'
	)
,
tmp as(
select
	distinct st.shipping_id,
	st.last_status,
	st.last_state,
	tt.first_date,
	tt.last_date
from
	status_tmp st
join times_tmp tt on
	st.shipping_id = tt.shipping_id)
insert
	into
	shipping_status(shipping_id,
	status,
	state,
	shipping_start_fact_datetime,
	shipping_end_fact_datetime)
select
	tmp.shipping_id,
	tmp.last_status,
	tmp.last_state,
	tmp.first_date,
	tmp.last_date
from
	tmp on
	conflict (shipping_id) do
update
set
	shipping_start_fact_datetime = excluded.first_date,
	shipping_end_fact_datetime = excluded.last_date;
