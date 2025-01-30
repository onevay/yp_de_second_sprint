--создание представления для анализа
create or replace view public.shipping_datamart
as
select
	distinct s.shipping_id,
	s.vendor_id,
	t.transfer_type,
	date_part('day',
	ss.shipping_end_fact_datetime - ss.shipping_start_fact_datetime) as full_day_at_shipping,
	(case
		when ss.shipping_end_fact_datetime > s.shipping_plan_datetime then 1
		else 0 end) is_delay,
		(case
			when ss.status like 'finished' then 1
		else 0 end) is_shipping_finish,
	(case
		when date_part('day', ss.shipping_end_fact_datetime - s.shipping_plan_datetime) > 0 then date_part('day', ss.shipping_end_fact_datetime - s.shipping_plan_datetime)
		else 0 end) delay_day_at_shipping,
	s.payment payment_amount,
	s.payment_amount * (s.shipping_country_base_rate + a.agreement_rate + t.shipping_transfer_rate) vat
from
	public.shipping_info si
left join public.shipping s on
	s.shipping_id = si.shippingid
left join public.shipping_agreement a on
	a.agreementid = si.shipping_agreement_id
left join public.shipping_transfer t on
	t.id = si.shipping_transfer_id
left join public.shipping_status ss on
	ss.shipping_id = si.shippingid
;


--просмотр содержимого
select * from public.shipping_datamart;