-- ════════════════════════════════════════════════
-- ЛОТУС — НЦТЛП Database Schema
-- ════════════════════════════════════════════════

-- ORGANIZATIONS (участники)
CREATE TABLE IF NOT EXISTS organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inn VARCHAR(12) UNIQUE NOT NULL,
  kpp VARCHAR(9),
  ogrn VARCHAR(15),
  full_name TEXT NOT NULL,
  short_name TEXT,
  legal_address TEXT,
  phone VARCHAR(30),
  email VARCHAR(100),
  contact_person TEXT,
  role TEXT[] DEFAULT '{}',  -- ['shipper','receiver','carrier','expeditor']
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- USERS
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  full_name TEXT NOT NULL,
  organization_id UUID REFERENCES organizations(id),
  role TEXT DEFAULT 'shipper',  -- shipper, foiv, admin
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- TRANSPORT LEGS (плечи маршрута)
CREATE TABLE IF NOT EXISTS transport_legs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sequence_number INTEGER NOT NULL,
  shipment_id UUID,  -- FK added later
  mode TEXT NOT NULL, -- auto, rail, sea, air
  from_point TEXT NOT NULL,
  to_point TEXT NOT NULL,
  carrier_org_id UUID REFERENCES organizations(id),
  carrier_name TEXT,
  status TEXT DEFAULT 'planned', -- planned, in_progress, completed, delayed
  current_location TEXT,
  distance_km INTEGER,
  departure_plan DATE,
  departure_fact DATE,
  arrival_plan DATE,
  arrival_fact DATE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- SHIPMENTS (перевозки / ЦПП)
CREATE TABLE IF NOT EXISTS shipments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cpp_number TEXT UNIQUE NOT NULL,  -- ЦПП-4407-2025-067
  trip_type TEXT NOT NULL,          -- Экспортная мультимодальная перевозка
  status TEXT DEFAULT 'active',     -- active, completed, cancelled
  -- Стороны сделки
  shipper_org_id UUID REFERENCES organizations(id),
  receiver_org_id UUID REFERENCES organizations(id),
  seller_org_id UUID REFERENCES organizations(id),
  exporter_org_id UUID REFERENCES organizations(id),
  coordinator_name TEXT,
  -- Маршрут
  origin_country TEXT,
  origin_address TEXT,
  destination_country TEXT,
  destination_address TEXT,
  -- Модальности (массив: auto, rail, sea, air)
  modalities TEXT[] DEFAULT '{}',
  -- Даты
  date_start DATE,
  date_end_plan DATE,
  date_end_fact DATE,
  -- Метрики ЦПП
  params_count INTEGER DEFAULT 70,
  data_sources_count INTEGER DEFAULT 10,
  documents_count INTEGER DEFAULT 23,
  -- Связанный пользователь
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add FK from transport_legs to shipments
ALTER TABLE transport_legs
  ADD CONSTRAINT fk_leg_shipment
  FOREIGN KEY (shipment_id) REFERENCES shipments(id) ON DELETE CASCADE;

-- CARGO (грузы)
CREATE TABLE IF NOT EXISTS cargo (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id UUID REFERENCES shipments(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  hs_code TEXT,
  packaging_type TEXT,
  weight_kg NUMERIC(12,2),
  volume_m3 NUMERIC(10,2),
  quantity INTEGER,
  unit TEXT,
  dangerous BOOLEAN DEFAULT false,
  temperature_controlled BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- DOCUMENTS (документы)
CREATE TABLE IF NOT EXISTS documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id UUID REFERENCES shipments(id) ON DELETE CASCADE,
  doc_type TEXT NOT NULL,  -- etrn, ttn, cmr, invoice, packing_list, customs_decl
  doc_number TEXT,
  status TEXT DEFAULT 'draft',  -- draft, signed, sent, accepted
  issued_by TEXT,
  issued_at TIMESTAMPTZ,
  signed_at TIMESTAMPTZ,
  file_url TEXT,
  source_system TEXT DEFAULT 'НЦТЛП',
  data_record_id TEXT,  -- DATA-xxx-000067
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- CPP DATA RECORDS (массив данных ЦПП)
CREATE TABLE IF NOT EXISTS cpp_data_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id UUID REFERENCES shipments(id) ON DELETE CASCADE,
  category TEXT NOT NULL,    -- 'trip_data', 'parties', 'cargo', 'documents'
  param_name TEXT NOT NULL,
  param_value TEXT,
  data_source TEXT,          -- Грузоотправитель, НЦТЛП, ФТС России
  system_gis TEXT,           -- НЦТЛП
  record_id TEXT,            -- DATA-TRIP-000067
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- AI QUERIES LOG
CREATE TABLE IF NOT EXISTS ai_queries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  query_text TEXT NOT NULL,
  response_text TEXT,
  model TEXT DEFAULT 'claude-sonnet-4-5-20250929',
  tokens_used INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- NOTIFICATIONS
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  shipment_id UUID REFERENCES shipments(id),
  type TEXT NOT NULL,  -- delay, document_required, status_change
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- NEWSLETTER SUBSCRIPTIONS
CREATE TABLE IF NOT EXISTS newsletter_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  subscribed_at TIMESTAMPTZ DEFAULT NOW()
);

-- ════════════════════════════════════════════════
-- SEED DATA — из Фигмы
-- ════════════════════════════════════════════════

-- Organizations
INSERT INTO organizations (inn, kpp, ogrn, full_name, short_name, legal_address, phone, role) VALUES
('5036028001','503601001','1025000004567',
 'Акционерное общество «ПодольскЛес»','АО «ПодольскЛес»',
 '142100, Московская обл., г. Подольск, ул. Большая Серпуховская, д. 214в',
 '+7 (495) 555-01-67',
 ARRAY['shipper','seller','exporter']),

('9310000MA1K4X9R','','91310000MA1K4X9RNN',
 'Shanghai Wood Import Co., Ltd','Shanghai Wood Import Co.',
 '200000, Shanghai, Pudong, No. 1 Trade Center',
 '',
 ARRAY['receiver']),

('7701234567','770101001','1057700123456',
 'ООО «ПодольскТранс»','ООО «ПодольскТранс»',
 'г. Подольск, ул. Промышленная, д. 5',
 '',
 ARRAY['carrier']),

('7702345678','770201001','1057700234567',
 'ООО «Белые Столбы-Логистика»','ООО «Белые Столбы-Логистика»',
 'Московская обл., Домодедово, СВХ Белые Столбы',
 '',
 ARRAY['carrier']),

('7703456789','770301001','1057700345678',
 'ООО «Цифровая Логистика»','ООО «Цифровая Логистика»',
 'г. Москва, ул. Тверская, д. 10',
 '',
 ARRAY['carrier']),

('7704567890','770401001','1057700456789',
 'ПАО «ДВМП»','ПАО «ДВМП»',
 'г. Владивосток, ул. Пограничная, д. 1',
 '',
 ARRAY['carrier']),

('6316000000','631601001','1026300000001',
 'ОАО «РЖД»','РЖД',
 'г. Москва, ул. Новая Басманная, д. 2',
 '',
 ARRAY['carrier']),

('7710000001','771001001','1027700001234',
 'ООО «ЭнергоТорг»','ООО ЭнергоТорг',
 'г. Москва, ул. Варшавское шоссе, д. 5',
 '',
 ARRAY['shipper']),

('7720000002','772001001','1027700002345',
 'ПАО «ТрансЛогик»','ПАО ТрансЛогик',
 'г. Санкт-Петербург, Лиговский пр., д. 10',
 '',
 ARRAY['shipper','carrier']),

('7730000003','773001001','1027700003456',
 'ЗАО «ЛогиСервис»','ЗАО ЛогиСервис',
 'г. Казань, ул. Баумана, д. 15',
 '',
 ARRAY['shipper']),

('7740000004','774001001','1027700004567',
 'АО «ГлобалТрейд»','АО ГлобалТрейд',
 'г. Новосибирск, пр. Красный, д. 20',
 '',
 ARRAY['shipper']),

('7750000005','775001001','1027700005678',
 'ПАО «МедСнаб»','ПАО МедСнаб',
 'г. Екатеринбург, ул. Мира, д. 3',
 '',
 ARRAY['shipper']),

('7760000006','776001001','1027700006789',
 'ООО «АзияИмпорт»','ООО АзияИмпорт',
 'г. Владивосток, ул. Светланская, д. 8',
 '',
 ARRAY['shipper']),

('7770000007','777001001','1027700007890',
 'ООО «ТекстильИмпорт»','ООО ТекстильИмпорт',
 'г. Иваново, пр. Шереметевский, д. 5',
 '',
 ARRAY['shipper']),

('7780000008','778001001','1027700008901',
 'ОАО «РусЭкспорт»','ОАО РусЭкспорт',
 'г. Москва, ул. Пятницкая, д. 12',
 '',
 ARRAY['shipper','exporter']),

('7790000009','779001001','1027700009012',
 'АО «ФудЛайн»','АО ФудЛайн',
 'г. Краснодар, ул. Красная, д. 5',
 '',
 ARRAY['shipper']),

('7800000010','780001001','1027700010123',
 'АО «СтальГрупп»','АО СтальГрупп',
 'г. Магнитогорск, пр. Металлургов, д. 1',
 '',
 ARRAY['shipper'])

ON CONFLICT (inn) DO NOTHING;

-- Users
INSERT INTO users (email, password_hash, full_name, role) VALUES
('test@lotus.ru', '$2b$10$placeholder_hash_here', 'Администратор ЛОТУС', 'admin'),
('shipper@podolskles.ru', '$2b$10$placeholder_hash_here', 'Иванов Иван Иванович', 'shipper')
ON CONFLICT (email) DO NOTHING;

-- Shipments — все 5 перевозок из Фигмы + дополнительные
WITH orgs AS (
  SELECT id, inn FROM organizations
)
INSERT INTO shipments (cpp_number, trip_type, status, modalities,
  origin_country, origin_address, destination_country, destination_address,
  date_start, date_end_plan, date_end_fact,
  coordinator_name, params_count, data_sources_count, documents_count,
  shipper_org_id, receiver_org_id)
SELECT
  v.cpp_number, v.trip_type, v.status, v.modalities::text[],
  v.origin_country, v.origin_address, v.destination_country, v.destination_address,
  v.date_start::date, v.date_end_plan::date, v.date_end_fact::date,
  v.coordinator_name, v.params_count, v.data_sources_count, v.documents_count,
  s.id, r.id
FROM (VALUES
  ('ЦПП-4407-2025-067','Экспортная мультимодальная перевозка','active',
   '{auto,rail,sea}',
   'Российская Федерация','Московская область, г. Подольск, ул. Большая Серпуховская, д. 214в',
   'Китайская Народная Республика','КНР, г. Шанхай, порт Шанхай',
   '2025-12-05','2025-12-28',NULL,
   'Иванов И.И.',70,10,23,
   '5036028001','9310000MA1K4X9R'),
  ('ЦПП-5502-2025-001','Внутренняя перевозка автомобильным транспортом','active',
   '{auto}',
   'Российская Федерация','г. Москва',
   'Российская Федерация','г. Архангельск',
   '2025-12-10','2025-12-10',NULL,
   'Сидоров В.В.',45,5,12,
   '7710000001','7720000002'),
  ('ЦПП-4406-2025-009','Внутренняя мультимодальная перевозка','active',
   '{rail,auto}',
   'Российская Федерация','г. Казань',
   'Российская Федерация','г. Екатеринбург',
   '2025-12-05','2025-12-14',NULL,
   'Кузнецов Д.Д.',38,4,8,
   '7730000003','7750000005'),
  ('ЦПП-4410-2025-018','Внутренняя мультимодальная перевозка','completed',
   '{sea,auto}',
   'Российская Федерация','г. Санкт-Петербург',
   'Российская Федерация','г. Калуга',
   '2025-05-01','2025-05-09','2025-05-09',
   'Смирнов Е.Е.',52,7,18,
   '7780000008','7760000006'),
  ('ЦПП-4411-2025-021','Внутренняя мультимодальная перевозка','completed',
   '{rail,auto}',
   'Российская Федерация','г. Новосибирск',
   'Российская Федерация','г. Владивосток',
   '2025-06-22','2025-07-01','2025-07-01',
   'Петров А.А.',61,8,20,
   '7740000004','7760000006')
) AS v(cpp_number,trip_type,status,modalities,
       origin_country,origin_address,destination_country,destination_address,
       date_start,date_end_plan,date_end_fact,
       coordinator_name,params_count,data_sources_count,documents_count,
       shipper_inn,receiver_inn)
JOIN orgs s ON s.inn = v.shipper_inn
JOIN orgs r ON r.inn = v.receiver_inn
ON CONFLICT (cpp_number) DO NOTHING;

-- Transport legs для ЦПП-4407-2025-067
WITH s AS (SELECT id FROM shipments WHERE cpp_number='ЦПП-4407-2025-067' LIMIT 1),
     c1 AS (SELECT id FROM organizations WHERE inn='7701234567' LIMIT 1),
     c2 AS (SELECT id FROM organizations WHERE inn='7703456789' LIMIT 1),
     c3 AS (SELECT id FROM organizations WHERE inn='7704567890' LIMIT 1)
INSERT INTO transport_legs (shipment_id, sequence_number, mode, from_point, to_point,
  carrier_org_id, carrier_name, status,
  departure_plan, departure_fact, arrival_plan, arrival_fact, distance_km)
SELECT s.id, leg.seq, leg.mode, leg.frm, leg.to_, org_id, leg.carrier_name, leg.status,
  leg.dep_plan::date, leg.dep_fact::date, leg.arr_plan::date, leg.arr_fact::date, leg.km
FROM (VALUES
  (1,'auto','г. Подольск, ул. Большая Серпуховская, д. 214в','СВХ «Белые Столбы»',
   (SELECT id FROM c1),'ООО «ПодольскТранс»','completed',
   '2025-12-05','2025-12-05','2025-12-05','2025-12-05',50),
  (2,'auto','СВХ «Белые Столбы»','ст. Ворсино',
   (SELECT id FROM c2),'ООО «Белые Столбы-Логистика»','completed',
   '2025-12-08','2025-12-08','2025-12-08','2025-12-08',80),
  (3,'rail','ст. Ворсино','Порт Владивосток',
   (SELECT id FROM c3),'ООО «Цифровая Логистика»','in_progress',
   '2025-12-08','2025-12-08','2025-12-14','2025-12-13',9189),
  (4,'sea','Порт Владивосток','Порт Шанхай',
   (SELECT id FROM c3),'ПАО «ДВМП»','planned',
   '2025-12-15',NULL,'2025-12-28',NULL,1850)
) AS leg(seq,mode,frm,to_,org_id,carrier_name,status,dep_plan,dep_fact,arr_plan,arr_fact,km),
s
ON CONFLICT DO NOTHING;

-- Cargo
WITH s AS (SELECT id FROM shipments WHERE cpp_number='ЦПП-4407-2025-067' LIMIT 1)
INSERT INTO cargo (shipment_id, name, packaging_type, weight_kg, volume_m3)
SELECT s.id, 'Пиломатериалы хвойные, обрезные, сушёные', 'Паллеты', 24000, 80
FROM s
ON CONFLICT DO NOTHING;

WITH s AS (SELECT id FROM shipments WHERE cpp_number='ЦПП-5502-2025-001' LIMIT 1)
INSERT INTO cargo (shipment_id, name, packaging_type, weight_kg)
SELECT s.id, 'Мясные консервы', 'Ящики', 5000
FROM s ON CONFLICT DO NOTHING;

WITH s AS (SELECT id FROM shipments WHERE cpp_number='ЦПП-4406-2025-009' LIMIT 1)
INSERT INTO cargo (shipment_id, name, packaging_type, weight_kg)
SELECT s.id, 'Удобрения', 'Мешки', 50000
FROM s ON CONFLICT DO NOTHING;

WITH s AS (SELECT id FROM shipments WHERE cpp_number='ЦПП-4410-2025-018' LIMIT 1)
INSERT INTO cargo (shipment_id, name, packaging_type, weight_kg)
SELECT s.id, 'Металлопрокат', 'Навалом', 120000
FROM s ON CONFLICT DO NOTHING;

WITH s AS (SELECT id FROM shipments WHERE cpp_number='ЦПП-4411-2025-021' LIMIT 1)
INSERT INTO cargo (shipment_id, name, packaging_type, weight_kg)
SELECT s.id, 'Бытовая техника', 'Паллеты', 18000
FROM s ON CONFLICT DO NOTHING;

-- CPP Data Records (массив данных ЦПП из Фигмы)
WITH s AS (SELECT id FROM shipments WHERE cpp_number='ЦПП-4407-2025-067' LIMIT 1)
INSERT INTO cpp_data_records (shipment_id, category, param_name, param_value, data_source, system_gis, record_id)
SELECT s.id, r.cat, r.param, r.val, r.src, r.sys, r.rid FROM s,
(VALUES
  ('trip_data','Тип перевозки','Экспортная мультимодальная перевозка','Грузоотправитель','НЦТЛП','DATA-TRIP-000067'),
  ('trip_data','Модальности','Автомобильный транспорт; Железнодорожный транспорт; Морской транспорт','Грузоотправитель','НЦТЛП','DATA-MODES-000067'),
  ('trip_data','Дата начала','05.12.2025','Грузоотправитель','НЦТЛП','DATA-DTSTART-000067'),
  ('trip_data','Дата окончания','28.12.2025 (план)','НЦТЛП','НЦТЛП','DATA-DTENDP-000067'),
  ('trip_data','Страна отправления','Российская Федерация (RU)','Грузоотправитель','НЦТЛП','DATA-ORIG-CTRY-000067'),
  ('trip_data','Страна назначения','Китайская Народная Республика (CN)','Грузоотправитель','НЦТЛП','DATA-DEST-CTRY-000067'),
  ('trip_data','Пункт отправления','РФ, Московская обл., г. Подольск, ул. Большая Серпуховская, д. 214в','Грузоотправитель','НЦТЛП','DATA-ORIG-ADDR-000067'),
  ('trip_data','Пункт назначения','КНР, г. Шанхай, порт Шанхай','Грузоотправитель','НЦТЛП','DATA-DEST-ADDR-000067'),
  ('parties','Продавец','АО «ПодольскЛес», ИНН 5036028001, КПП 503601001, ОГРН 1025000004567','Грузоотправитель','НЦТЛП','PARTY-SELL-000067'),
  ('parties','Грузоотправитель','АО «ПодольскЛес», ИНН 5036028001, КПП 503601001, контакт: отдел логистики, тел.: +7 (495) 555-01-67','Грузоотправитель','НЦТЛП','PARTY-SHIP-000067'),
  ('parties','Экспортёр','АО «ПодольскЛес», ИНН 5036028001, ОГРН 1025000004567','НЦТЛП','НЦТЛП','PARTY-EXP-000067'),
  ('parties','Получатель','Shanghai Wood Import Co., Ltd, Reg. No. 91310000MA1K4X9RNN, 200000, Shanghai, Pudong','Грузополучатель','НЦТЛП','PARTY-CONS-000067')
) AS r(cat,param,val,src,sys,rid)
ON CONFLICT DO NOTHING;

-- Notifications
WITH u AS (SELECT id FROM users WHERE email='shipper@podolskles.ru' LIMIT 1),
     s AS (SELECT id FROM shipments WHERE cpp_number='ЦПП-5502-2025-001' LIMIT 1)
INSERT INTO notifications (user_id, shipment_id, type, message, is_read)
SELECT u.id, s.id, 'delay', 'Перевозка ЦПП-5502-2025-001: задержка отправления на 8 дней', false
FROM u, s ON CONFLICT DO NOTHING;
