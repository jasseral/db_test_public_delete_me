--
-- PostgreSQL database dump
--

-- Dumped from database version 11.2
-- Dumped by pg_dump version 11.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: clause; Type: SCHEMA; Schema: -; Owner: syntheia
--

CREATE SCHEMA clause;


ALTER SCHEMA clause OWNER TO syntheia;

--
-- Name: concept; Type: SCHEMA; Schema: -; Owner: syntheia
--

CREATE SCHEMA concept;


ALTER SCHEMA concept OWNER TO syntheia;

--
-- Name: drafting; Type: SCHEMA; Schema: -; Owner: syntheia
--

CREATE SCHEMA drafting;


ALTER SCHEMA drafting OWNER TO syntheia;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: fix_document_chain(integer[]); Type: FUNCTION; Schema: clause; Owner: syntheia
--

CREATE FUNCTION clause.fix_document_chain(doc_chain_ids integer[]) RETURNS void
    LANGUAGE sql
    AS $$
	WITH changed AS (
		SELECT
			doc_id,
			doc_version_active,
			LAST_VALUE(doc_id) OVER (PARTITION BY doc_chain_id ORDER BY doc_version ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) = doc_id new_doc_version_active
		FROM clause.documents
		WHERE doc_chain_id = ANY(doc_chain_ids)
	)

	UPDATE clause.documents d
		SET doc_version_active = changed.new_doc_version_active
	FROM changed
	WHERE changed.doc_id = d.doc_id
		AND changed.doc_version_active IS DISTINCT FROM changed.new_doc_version_active
$$;


ALTER FUNCTION clause.fix_document_chain(doc_chain_ids integer[]) OWNER TO syntheia;

--
-- Name: tags_unaccent_tr(); Type: FUNCTION; Schema: clause; Owner: syntheia
--

CREATE FUNCTION clause.tags_unaccent_tr() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	NEW.tag_name_unaccented = unaccent(NEW.tag_name);

	RETURN NEW;
END;
$$;


ALTER FUNCTION clause.tags_unaccent_tr() OWNER TO syntheia;

--
-- Name: get_full_tag_name(integer[]); Type: FUNCTION; Schema: public; Owner: syntheia
--

CREATE FUNCTION public.get_full_tag_name(p_tag_id integer[]) RETURNS text[]
    LANGUAGE sql STABLE STRICT
    AS $$
	SELECT
		ARRAY_AGG(get_full_tag_name(single_tag_id))
	FROM UNNEST(p_tag_id) AS un(single_tag_id)
$$;


ALTER FUNCTION public.get_full_tag_name(p_tag_id integer[]) OWNER TO syntheia;

--
-- Name: get_full_tag_name(integer); Type: FUNCTION; Schema: public; Owner: syntheia
--

CREATE FUNCTION public.get_full_tag_name(p_tag_id integer) RETURNS text
    LANGUAGE sql STABLE STRICT
    AS $$
	WITH RECURSIVE q AS (
		SELECT 0 AS level, t.tag_id, t.parent_id, t.tag_name
		FROM clause.tags t
		WHERE t.tag_id = p_tag_id

		UNION ALL

		SELECT q.level - 1 AS level, t.tag_id, t.parent_id, t.tag_name
		FROM q
			JOIN clause.tags t ON (t.tag_id = q.parent_id)
	)

	SELECT STRING_AGG(tag_name, ' / ' ORDER BY level)
	FROM q
$$;


ALTER FUNCTION public.get_full_tag_name(p_tag_id integer) OWNER TO syntheia;

--
-- Name: get_user_object_stats(integer, integer); Type: FUNCTION; Schema: public; Owner: syntheia
--

CREATE FUNCTION public.get_user_object_stats(_owner_id integer, _app_user_id integer, OUT like_status smallint, OUT is_favorite boolean, OUT stats jsonb) RETURNS record
    LANGUAGE sql STABLE
    AS $$
	SELECT
		MAX(uof.like_status) FILTER (WHERE uof.app_user_id = _app_user_id) like_status,
		BOOL_OR(uof.is_favorite) FILTER (WHERE uof.app_user_id = _app_user_id) is_favorite,

		JSONB_BUILD_OBJECT(
			'liked', COUNT(*) FILTER (WHERE uof.like_status = 1 /* LIKE_STATUS_LIKE */),
			'disliked', COUNT(*) FILTER (WHERE uof.like_status = -1 /* LIKE_STATUS_DISLIKE */),
			'favourited', COUNT(*) FILTER (WHERE uof.is_favorite)
		) stats
	FROM clause.user_object_flags uof
	WHERE uof.owner_id = _owner_id
$$;


ALTER FUNCTION public.get_user_object_stats(_owner_id integer, _app_user_id integer, OUT like_status smallint, OUT is_favorite boolean, OUT stats jsonb) OWNER TO syntheia;

--
-- Name: split_text_into_trigrams(text); Type: FUNCTION; Schema: public; Owner: syntheia
--

CREATE FUNCTION public.split_text_into_trigrams(_text text) RETURNS SETOF text
    LANGUAGE sql
    AS $$
	WITH words AS (
		SELECT * FROM regexp_split_to_table(_text, '\s') with ordinality as t(word, ordr)
	), trigrams AS (
		SELECT
			STRING_AGG(word, E'\n') OVER (ORDER BY ordr RANGE BETWEEN 2 PRECEDING AND CURRENT ROW) trigram,
			ordr
		FROM words
	)

	SELECT trigram
	FROM trigrams
	WHERE ordr > 2
$$;


ALTER FUNCTION public.split_text_into_trigrams(_text text) OWNER TO syntheia;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: clause_document_link; Type: TABLE; Schema: clause; Owner: syntheia
--

CREATE TABLE clause.clause_document_link (
    document_id integer NOT NULL,
    clause_id integer NOT NULL,
    parent_clause_id integer,
    clause_depth integer
);


ALTER TABLE clause.clause_document_link OWNER TO syntheia;

--
-- Name: clause_word_trigrams; Type: TABLE; Schema: clause; Owner: syntheia
--

CREATE TABLE clause.clause_word_trigrams (
    clause_type_id integer NOT NULL,
    word_trigram text NOT NULL,
    ct integer NOT NULL
);


ALTER TABLE clause.clause_word_trigrams OWNER TO syntheia;

--
-- Name: large_id_seq; Type: SEQUENCE; Schema: public; Owner: syntheia
--

CREATE SEQUENCE public.large_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.large_id_seq OWNER TO syntheia;

--
-- Name: clause_word_trigrams_updates; Type: TABLE; Schema: clause; Owner: syntheia
--

CREATE TABLE clause.clause_word_trigrams_updates (
    clause_word_trigrams_update_id integer DEFAULT nextval('public.large_id_seq'::regclass) NOT NULL,
    clause_type_id integer[] NOT NULL,
    clause_text text NOT NULL,
    add boolean NOT NULL
);


ALTER TABLE clause.clause_word_trigrams_updates OWNER TO syntheia;

--
-- Name: id_seq; Type: SEQUENCE; Schema: public; Owner: syntheia
--

CREATE SEQUENCE public.id_seq
    START WITH 1000000
    INCREMENT BY 1
    MINVALUE 1000000
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.id_seq OWNER TO syntheia;

--
-- Name: clauses; Type: TABLE; Schema: clause; Owner: syntheia
--

CREATE TABLE clause.clauses (
    clause_id integer DEFAULT nextval('public.id_seq'::regclass) NOT NULL,
    practice_group_id integer[],
    title text,
    clause_date_from date DEFAULT now() NOT NULL,
    date_last_modified timestamp with time zone DEFAULT now() NOT NULL,
    jurisdiction_id integer[],
    sector_id integer[],
    lip_id uuid,
    is_deleted boolean DEFAULT false NOT NULL,
    is_endorsed boolean DEFAULT false NOT NULL,
    hash bytea NOT NULL,
    party_id integer[],
    clause_type_id integer[],
    client_id integer[],
    author_id integer[],
    manual boolean DEFAULT false NOT NULL,
    clause_date_to date DEFAULT now() NOT NULL,
    clause_text text NOT NULL,
    is_validated boolean DEFAULT false NOT NULL,
    document_type_id integer[]
);


ALTER TABLE clause.clauses OWNER TO syntheia;

--
-- Name: comments; Type: TABLE; Schema: clause; Owner: syntheia
--

CREATE TABLE clause.comments (
    comment_id integer DEFAULT nextval('public.id_seq'::regclass) NOT NULL,
    owner_id integer NOT NULL,
    comment_text text NOT NULL,
    date_added timestamp with time zone DEFAULT now() NOT NULL,
    app_user_id integer NOT NULL
);


ALTER TABLE clause.comments OWNER TO syntheia;

--
-- Name: documents; Type: TABLE; Schema: clause; Owner: syntheia
--

CREATE TABLE clause.documents (
    doc_id integer DEFAULT nextval('public.id_seq'::regclass) NOT NULL,
    practice_group_id integer[],
    doc_file_name text,
    doc_title text,
    doc_version integer NOT NULL,
    doc_date date DEFAULT now() NOT NULL,
    date_last_modified timestamp with time zone DEFAULT now() NOT NULL,
    date_uploaded timestamp with time zone DEFAULT now() NOT NULL,
    doc_chain_id integer NOT NULL,
    doc_version_active boolean DEFAULT true NOT NULL,
    jurisdiction_id integer[],
    sector_id integer[],
    is_endorsed boolean DEFAULT false NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    lip_id uuid,
    party_id integer[],
    document_type_id integer[],
    client_id integer[],
    author_id integer[],
    document_state integer[],
    hash bytea,
    mmapi_id text,
    original_file_id integer,
    xml_file_id integer,
    segmented_xml_file_id integer
);


ALTER TABLE clause.documents OWNER TO syntheia;

--
-- Name: tags; Type: TABLE; Schema: clause; Owner: syntheia
--

CREATE TABLE clause.tags (
    tag_id integer DEFAULT nextval('public.id_seq'::regclass) NOT NULL,
    tag_name text NOT NULL,
    tag_name_unaccented text NOT NULL,
    parent_id integer,
    lip_id uuid,
    tag_type text NOT NULL,
    owner_id integer
);


ALTER TABLE clause.tags OWNER TO syntheia;

--
-- Name: user_object_flags; Type: TABLE; Schema: clause; Owner: syntheia
--

CREATE TABLE clause.user_object_flags (
    owner_id integer NOT NULL,
    app_user_id integer NOT NULL,
    is_favorite boolean DEFAULT false NOT NULL,
    like_status smallint DEFAULT 0 NOT NULL
);


ALTER TABLE clause.user_object_flags OWNER TO syntheia;

--
-- Name: concepts; Type: TABLE; Schema: concept; Owner: syntheia
--

CREATE TABLE concept.concepts (
    concept_id integer DEFAULT nextval('public.id_seq'::regclass) NOT NULL,
    document_type_id integer,
    clause_type_id integer,
    mmapi_category_id text NOT NULL,
    mmapi_model_id text NOT NULL,
    needs_training boolean DEFAULT false NOT NULL,
    training_error text,
    is_internal boolean DEFAULT false NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    is_endorsed boolean DEFAULT false NOT NULL,
    mmapi_lastupdated timestamp with time zone,
    suite_id integer[],
    practice_group_id integer[],
    jurisdiction_id integer[],
    sector_id integer[],
    name text NOT NULL,
    CONSTRAINT concepts_ck_internal CHECK (
CASE
    WHEN is_internal THEN ((document_type_id IS NOT NULL) AND (clause_type_id IS NOT NULL))
    ELSE ((document_type_id IS NULL) AND (clause_type_id IS NULL))
END)
);


ALTER TABLE concept.concepts OWNER TO syntheia;

--
-- Name: document_updates; Type: TABLE; Schema: concept; Owner: syntheia
--

CREATE TABLE concept.document_updates (
    document_update_id integer DEFAULT nextval('public.large_id_seq'::regclass) NOT NULL,
    doc_id integer NOT NULL,
    document_type_id integer[],
    clause_type_id integer[]
);


ALTER TABLE concept.document_updates OWNER TO syntheia;

--
-- Name: activities; Type: TABLE; Schema: public; Owner: syntheia
--

CREATE TABLE public.activities (
    activity_id integer DEFAULT nextval('public.id_seq'::regclass) NOT NULL,
    activity_time timestamp with time zone DEFAULT now() NOT NULL,
    activity_type text NOT NULL,
    app_user_id integer NOT NULL,
    activity_data jsonb,
    owner_id integer
);


ALTER TABLE public.activities OWNER TO syntheia;

--
-- Name: app_users; Type: TABLE; Schema: public; Owner: syntheia
--

CREATE TABLE public.app_users (
    app_user_id integer DEFAULT nextval('public.id_seq'::regclass) NOT NULL,
    firstname text NOT NULL,
    lastname text NOT NULL,
    password text NOT NULL,
    email text NOT NULL,
    user_type integer DEFAULT 100 NOT NULL,
    active boolean DEFAULT true
);


ALTER TABLE public.app_users OWNER TO syntheia;

--
-- Name: job_schedules; Type: TABLE; Schema: public; Owner: syntheia
--

CREATE TABLE public.job_schedules (
    job_schedule_id integer DEFAULT nextval('public.id_seq'::regclass) NOT NULL,
    job_type text NOT NULL,
    job_data jsonb,
    next_time timestamp with time zone,
    calc_next_time text
);


ALTER TABLE public.job_schedules OWNER TO syntheia;

--
-- Name: jobs; Type: TABLE; Schema: public; Owner: syntheia
--

CREATE TABLE public.jobs (
    job_id integer DEFAULT nextval('public.large_id_seq'::regclass) NOT NULL,
    queued timestamp with time zone DEFAULT now() NOT NULL,
    started timestamp with time zone,
    ended timestamp with time zone,
    error text,
    job_type text NOT NULL,
    job_data jsonb,
    error_acknowledged boolean
);


ALTER TABLE public.jobs OWNER TO syntheia;

--
-- Name: upgrades; Type: TABLE; Schema: public; Owner: syntheia
--

CREATE TABLE public.upgrades (
    id integer NOT NULL,
    upgradetime timestamp with time zone DEFAULT now() NOT NULL,
    current_id integer DEFAULT nextval('public.id_seq'::regclass) NOT NULL
);


ALTER TABLE public.upgrades OWNER TO syntheia;

--
-- Data for Name: clause_document_link; Type: TABLE DATA; Schema: clause; Owner: syntheia
--

COPY clause.clause_document_link (document_id, clause_id, parent_clause_id, clause_depth) FROM stdin;
\.


--
-- Data for Name: clause_word_trigrams; Type: TABLE DATA; Schema: clause; Owner: syntheia
--

COPY clause.clause_word_trigrams (clause_type_id, word_trigram, ct) FROM stdin;
\.


--
-- Data for Name: clause_word_trigrams_updates; Type: TABLE DATA; Schema: clause; Owner: syntheia
--

COPY clause.clause_word_trigrams_updates (clause_word_trigrams_update_id, clause_type_id, clause_text, add) FROM stdin;
\.


--
-- Data for Name: clauses; Type: TABLE DATA; Schema: clause; Owner: syntheia
--

COPY clause.clauses (clause_id, practice_group_id, title, clause_date_from, date_last_modified, jurisdiction_id, sector_id, lip_id, is_deleted, is_endorsed, hash, party_id, clause_type_id, client_id, author_id, manual, clause_date_to, clause_text, is_validated, document_type_id) FROM stdin;
\.


--
-- Data for Name: comments; Type: TABLE DATA; Schema: clause; Owner: syntheia
--

COPY clause.comments (comment_id, owner_id, comment_text, date_added, app_user_id) FROM stdin;
\.


--
-- Data for Name: documents; Type: TABLE DATA; Schema: clause; Owner: syntheia
--

COPY clause.documents (doc_id, practice_group_id, doc_file_name, doc_title, doc_version, doc_date, date_last_modified, date_uploaded, doc_chain_id, doc_version_active, jurisdiction_id, sector_id, is_endorsed, is_deleted, lip_id, party_id, document_type_id, client_id, author_id, document_state, hash, mmapi_id, original_file_id, xml_file_id, segmented_xml_file_id) FROM stdin;
\.


--
-- Data for Name: tags; Type: TABLE DATA; Schema: clause; Owner: syntheia
--

COPY clause.tags (tag_id, tag_name, tag_name_unaccented, parent_id, lip_id, tag_type, owner_id) FROM stdin;
1000102	Air	Air	1000029	\N	PracticeGroup	\N
1000084	Enforcement	Enforcement	1000025	\N	PracticeGroup	\N
1019492	hfgdghfg	hfgdghfg	\N	\N	Party	\N
1007818	Hawaii	Hawaii	1002544	\N	Jurisdiction	\N
1005445	Styria	Styria	1002325	\N	Jurisdiction	\N
1005446	Tyrol	Tyrol	1002325	\N	Jurisdiction	\N
1002524	Sweden	Sweden	\N	\N	Jurisdiction	\N
1002449	Mayotte	Mayotte	\N	\N	Jurisdiction	\N
1006372	Qom	Qom	1002411	\N	Jurisdiction	\N
1002468	Nigeria	Nigeria	\N	\N	Jurisdiction	\N
1005762	Yunnan	Yunnan	1002355	\N	Jurisdiction	\N
1007137	Fajardo	Fajardo	1002486	\N	Jurisdiction	\N
1008024	Energy	Energy	\N	\N	Sector	\N
1008109	Software	Software	1008051	\N	Sector	\N
1005359	Laghm??n	Laghman	1002312	\N	Jurisdiction	\N
1005364	Nangarh??r	Nangarhar	1002312	\N	Jurisdiction	\N
1005370	Farah	Farah	1002312	\N	Jurisdiction	\N
1005375	Saint John	Saint John	1002320	\N	Jurisdiction	\N
1005381	Dib??r	Diber	1002314	\N	Jurisdiction	\N
1005386	Berat	Berat	1002314	\N	Jurisdiction	\N
1005391	Armavir Province	Armavir Province	1002322	\N	Jurisdiction	\N
1005396	Aragatsotn Province	Aragatsotn Province	1002322	\N	Jurisdiction	\N
1005404	Luanda	Luanda	1002318	\N	Jurisdiction	\N
1005409	Cuando Cubango	Cuando Cubango	1002318	\N	Jurisdiction	\N
1005417	Entre Rios	Entre Rios	1002321	\N	Jurisdiction	\N
1005426	Cordoba	Cordoba	1002321	\N	Jurisdiction	\N
1005432	Jujuy	Jujuy	1002321	\N	Jurisdiction	\N
1005438	Eastern District	Eastern District	1002316	\N	Jurisdiction	\N
1005448	Western Australia	Western Australia	1002324	\N	Jurisdiction	\N
1005457	Saatl??	Saatli	1002326	\N	Jurisdiction	\N
1005463	??mi??li	Imisli	1002326	\N	Jurisdiction	\N
1005469	Shirvan	Shirvan	1002326	\N	Jurisdiction	\N
1000056	Public health and welfare	Public health and welfare	1000018	\N	PracticeGroup	\N
1000060	Banking regulations	Banking regulations	1000019	\N	PracticeGroup	\N
1000065	Unfair business practice	Unfair business practice	1000020	\N	PracticeGroup	\N
1000071	Mergers and acquisitions	Mergers and acquisitions	1000023	\N	PracticeGroup	\N
1000134	Sales	Sales	1000043	\N	PracticeGroup	\N
1000076	Business and financial crimes	Business and financial crimes	1000024	\N	PracticeGroup	\N
1007801	Rhode Island	Rhode Island	1002544	\N	Jurisdiction	\N
1007823	Canelones	Canelones	1002545	\N	Jurisdiction	\N
1007838	Karakalpakstan	Karakalpakstan	1002546	\N	Jurisdiction	\N
1007856	Gu??rico	Guarico	1002549	\N	Jurisdiction	\N
1007875	Monagas	Monagas	1002549	\N	Jurisdiction	\N
1007890	B??nh D????ng	Binh Duong	1002550	\N	Jurisdiction	\N
1006408	Manchester	Manchester	1002418	\N	Jurisdiction	\N
1006427	Fukuoka	Fukuoka	1002419	\N	Jurisdiction	\N
1006441	Shizuoka	Shizuoka	1002419	\N	Jurisdiction	\N
1006460	Kagoshima	Kagoshima	1002419	\N	Jurisdiction	\N
1006475	Laikipia	Laikipia	1002423	\N	Jurisdiction	\N
1006491	Lamu	Lamu	1002423	\N	Jurisdiction	\N
1007921	H???i Ph??ng	Hai Phong	1002550	\N	Jurisdiction	\N
1007941	Circonscription d'Uv??a	Circonscription d'Uvea	1002551	\N	Jurisdiction	\N
1007964	Al Bay???????	Al Bayda??	1002553	\N	Jurisdiction	\N
1006522	Banteay Meanchey	Banteay Meanchey	1002347	\N	Jurisdiction	\N
1006530	Koh Kong	Koh Kong	1002347	\N	Jurisdiction	\N
1006534	Kampong Speu	Kampong Speu	1002347	\N	Jurisdiction	\N
1002348	Cameroon	Cameroon	\N	\N	Jurisdiction	\N
1002362	Croatia	Croatia	\N	\N	Jurisdiction	\N
1002368	Denmark	Denmark	\N	\N	Jurisdiction	\N
1002373	Ecuador	Ecuador	\N	\N	Jurisdiction	\N
1002378	Estonia	Estonia	\N	\N	Jurisdiction	\N
1002384	France	France	\N	\N	Jurisdiction	\N
1002387	French Southern Territories	French Southern Territories	\N	\N	Jurisdiction	\N
1002398	Guam	Guam	\N	\N	Jurisdiction	\N
1002402	Guinea-Bissau	Guinea-Bissau	\N	\N	Jurisdiction	\N
1002410	Indonesia	Indonesia	\N	\N	Jurisdiction	\N
1002452	Moldova	Moldova	\N	\N	Jurisdiction	\N
1002458	Mozambique	Mozambique	\N	\N	Jurisdiction	\N
1002314	Albania	Albania	\N	\N	Jurisdiction	\N
1002329	Bangladesh	Bangladesh	\N	\N	Jurisdiction	\N
1002338	Bonaire, Saint Eustatius and Saba	Bonaire, Saint Eustatius and Saba	\N	\N	Jurisdiction	\N
1002367	Democratic Republic of the Congo	Democratic Republic of the Congo	\N	\N	Jurisdiction	\N
1002401	Guinea	Guinea	\N	\N	Jurisdiction	\N
1002414	Isle of Man	Isle of Man	\N	\N	Jurisdiction	\N
1008125	Real Estate Management & Development	Real Estate Management & Development	1008054	\N	Sector	\N
1008119	Electric Utilities	Electric Utilities	1008055	\N	Sector	\N
1008120	Gas Utilities	Gas Utilities	1008055	\N	Sector	\N
1008123	Independent Power and Renewable Electricity Producers	Independent Power and Renewable Electricity Producers	1008055	\N	Sector	\N
1008121	Multi-Utilities	Multi-Utilities	1008055	\N	Sector	\N
1008122	Water Utilities	Water Utilities	1008055	\N	Sector	\N
1007253	Mariy-El	Mariy-El	1002491	\N	Jurisdiction	\N
1007255	Saratov	Saratov	1002491	\N	Jurisdiction	\N
1007256	Komi Republic	Komi Republic	1002491	\N	Jurisdiction	\N
1007257	Lipetsk	Lipetsk	1002491	\N	Jurisdiction	\N
1007258	Tula	Tula	1002491	\N	Jurisdiction	\N
1008100	Life sciences tools and services	Life sciences tools and services	1008046	\N	Sector	\N
1008099	Pharmaceuticals	Pharmaceuticals	1008046	\N	Sector	\N
1002429	Latvia	Latvia	\N	\N	Jurisdiction	\N
1002464	New Caledonia	New Caledonia	\N	\N	Jurisdiction	\N
1002470	Norfolk Island	Norfolk Island	\N	\N	Jurisdiction	\N
1002486	Puerto Rico	Puerto Rico	\N	\N	Jurisdiction	\N
1002497	Saint Martin	Saint Martin	\N	\N	Jurisdiction	\N
1002419	Japan	Japan	\N	\N	Jurisdiction	\N
1002424	Kiribati	Kiribati	\N	\N	Jurisdiction	\N
1002430	Lebanon	Lebanon	\N	\N	Jurisdiction	\N
1002356	Christmas Island	Christmas Island	\N	\N	Jurisdiction	\N
1008064	Aerospace and defense	Aerospace and defense	1008047	\N	Sector	\N
1008065	Building products	Building products	1008047	\N	Sector	\N
1008066	Construction and engineering	Construction and engineering	1008047	\N	Sector	\N
1008067	Electrical equipment	Electrical equipment	1008047	\N	Sector	\N
1008068	Industrial conglomerates	Industrial conglomerates	1008047	\N	Sector	\N
1008069	Machinery	Machinery	1008047	\N	Sector	\N
1008070	Trading companies and distributors	Trading companies and distributors	1008047	\N	Sector	\N
1008071	Commercial services and supplies	Commercial services and supplies	1008048	\N	Sector	\N
1008072	Professional services	Professional services	1008048	\N	Sector	\N
1008073	Air freight and logistics	Air freight and logistics	1008049	\N	Sector	\N
1008074	Airlines	Airlines	1008049	\N	Sector	\N
1008075	Marine	Marine	1008049	\N	Sector	\N
1008076	Road and rail	Road and rail	1008049	\N	Sector	\N
1008108	IT services	IT services	1008051	\N	Sector	\N
1002436	Luxembourg	Luxembourg	\N	\N	Jurisdiction	\N
1002441	Malaysia	Malaysia	\N	\N	Jurisdiction	\N
1002448	Mauritius	Mauritius	\N	\N	Jurisdiction	\N
1002533	Trinidad and Tobago	Trinidad and Tobago	\N	\N	Jurisdiction	\N
1005416	Buenos Aires F.D.	Buenos Aires F.D.	1002321	\N	Jurisdiction	\N
1005436	Santa Cruz	Santa Cruz	1002321	\N	Jurisdiction	\N
1005452	New South Wales	New South Wales	1002324	\N	Jurisdiction	\N
1007708	Zanzibar Urban/West	Zanzibar Urban/West	1002529	\N	Jurisdiction	\N
1007735	Pemba South	Pemba South	1002529	\N	Jurisdiction	\N
1007746	Dnipropetrovsk	Dnipropetrovsk	1002541	\N	Jurisdiction	\N
1007765	Central Region	Central Region	1002540	\N	Jurisdiction	\N
1007788	South Carolina	South Carolina	1002544	\N	Jurisdiction	\N
1005567	Atakora	Atakora	1002334	\N	Jurisdiction	\N
1005581	Brunei and Muara	Brunei and Muara	1002343	\N	Jurisdiction	\N
1005604	Santa Catarina	Santa Catarina	1002341	\N	Jurisdiction	\N
1005627	South East	South East	1002340	\N	Jurisdiction	\N
1005642	British Columbia	British Columbia	1002349	\N	Jurisdiction	\N
1005669	K??mo	Kemo	1002352	\N	Jurisdiction	\N
1005680	Pointe-Noire	Pointe-Noire	1002488	\N	Jurisdiction	\N
1005698	Neuch??tel	Neuchatel	1002525	\N	Jurisdiction	\N
1005702	Thurgau	Thurgau	1002525	\N	Jurisdiction	\N
1005718	Worodougou	Worodougou	1002417	\N	Jurisdiction	\N
1005732	Santiago Metropolitan	Santiago Metropolitan	1002354	\N	Jurisdiction	\N
1005758	Shanghai Shi	Shanghai Shi	1002355	\N	Jurisdiction	\N
1005783	Antioquia	Antioquia	1002358	\N	Jurisdiction	\N
1005798	Risaralda	Risaralda	1002358	\N	Jurisdiction	\N
1005801	Archipi??lago de San Andr??s, Providencia y Santa Catalina	Archipielago de San Andres, Providencia y Santa Catalina	1002358	\N	Jurisdiction	\N
1005850	Moravskoslezsk??	Moravskoslezsky	1002366	\N	Jurisdiction	\N
1005880	Capital Region	Capital Region	1002368	\N	Jurisdiction	\N
1005897	Santiago Rodr??guez	Santiago Rodriguez	1002371	\N	Jurisdiction	\N
1005921	Adrar	Adrar	1002315	\N	Jurisdiction	\N
1005935	Sidi Bel Abb??s	Sidi Bel Abbes	1002315	\N	Jurisdiction	\N
1007902	?????ng Th??p	Dong Thap	1002550	\N	Jurisdiction	\N
1006025	Castille-La Mancha	Castille-La Mancha	1002518	\N	Jurisdiction	\N
1006041	Southern Nations, Nationalities, and People's Region	Southern Nations, Nationalities, and People's Region	1002379	\N	Jurisdiction	\N
1006085	Languedoc-Roussillon-Midi-Pyr??n??es	Languedoc-Roussillon-Midi-Pyrenees	1002384	\N	Jurisdiction	\N
1006130	Nzerekore	Nzerekore	1002401	\N	Jurisdiction	\N
1006144	West Greece	West Greece	1002394	\N	Jurisdiction	\N
1006153	Totonicap??n	Totonicapan	1002399	\N	Jurisdiction	\N
1006172	Santa Rosa	Santa Rosa	1002399	\N	Jurisdiction	\N
1006188	Kowloon City	Kowloon City	1002406	\N	Jurisdiction	\N
1006303	Andhra Pradesh	Andhra Pradesh	1002409	\N	Jurisdiction	\N
1006324	Andaman and Nicobar Islands	Andaman and Nicobar Islands	1002409	\N	Jurisdiction	\N
1006348	Maysan	Maysan	1002412	\N	Jurisdiction	\N
1006355	Kohg??l??yeh va B??yer A???mad	Kohgiluyeh va Buyer Ahmad	1002411	\N	Jurisdiction	\N
1006497	Kericho	Kericho	1002423	\N	Jurisdiction	\N
1006511	Jalal-Abad	Jalal-Abad	1002427	\N	Jurisdiction	\N
1007977	Western Cape	Western Cape	1002514	\N	Jurisdiction	\N
1007983	Copperbelt	Copperbelt	1002554	\N	Jurisdiction	\N
1007987	Masvingo	Masvingo	1002555	\N	Jurisdiction	\N
1006551	Hamgy??ng-bukto	Hamgyong-bukto	1002471	\N	Jurisdiction	\N
1006575	Mub??rak al Kab??r	Mubarak al Kabir	1002426	\N	Jurisdiction	\N
1006601	Bolikhamsai Province	Bolikhamsai Province	1002428	\N	Jurisdiction	\N
1006623	Grand Gedeh	Grand Gedeh	1002432	\N	Jurisdiction	\N
1006639	Utenos apskritis	Utenos apskritis	1002435	\N	Jurisdiction	\N
1006660	J??kabpils Municipality	Jekabpils Municipality	1002429	\N	Jurisdiction	\N
1006683	Sha???b??yat W??d?? al ???ay??t	Sha'biyat Wadi al Hayat	1002433	\N	Jurisdiction	\N
1006720	Cetinje	Cetinje	1002455	\N	Jurisdiction	\N
1000138	Derivatives	Derivatives	1000046	\N	PracticeGroup	\N
1000104	Marine and ocean	Marine and ocean	1000029	\N	PracticeGroup	\N
1000105	Mining	Mining	1000029	\N	PracticeGroup	\N
1000106	Waste and remediation	Waste and remediation	1000029	\N	PracticeGroup	\N
1000107	Water	Water	1000029	\N	PracticeGroup	\N
1002353	Chad	Chad	\N	\N	Jurisdiction	\N
1002354	Chile	Chile	\N	\N	Jurisdiction	\N
1002355	China	China	\N	\N	Jurisdiction	\N
1002357	Cocos Islands	Cocos Islands	\N	\N	Jurisdiction	\N
1002359	Comoros	Comoros	\N	\N	Jurisdiction	\N
1006782	Centar ??upa	Centar Zupa	1002438	\N	Jurisdiction	\N
1006790	Bamako	Bamako	1002443	\N	Jurisdiction	\N
1006804	Chin	Chin	1002459	\N	Jurisdiction	\N
1006819	Bulgan	Bulgan	1002454	\N	Jurisdiction	\N
1006830	Dakhlet Nouadhibou	Dakhlet Nouadhibou	1002447	\N	Jurisdiction	\N
1006861	Veracruz	Veracruz	1002450	\N	Jurisdiction	\N
1007027	Otago	Otago	1002465	\N	Jurisdiction	\N
1007032	Ash Sharqiyah South Governorate	Ash Sharqiyah South Governorate	1002474	\N	Jurisdiction	\N
1007070	Ayacucho	Ayacucho	1002481	\N	Jurisdiction	\N
1007086	Western Province	Western Province	1002479	\N	Jurisdiction	\N
1007111	Masovian Voivodeship	Masovian Voivodeship	1002484	\N	Jurisdiction	\N
1007143	Ponce	Ponce	1002486	\N	Jurisdiction	\N
1007155	Leiria	Leiria	1002485	\N	Jurisdiction	\N
1007170	Melekeok	Melekeok	1002476	\N	Jurisdiction	\N
1007184	Balad??yat Umm ??al??l	Baladiyat Umm Salal	1002487	\N	Jurisdiction	\N
1007212	Bihor	Bihor	1002490	\N	Jurisdiction	\N
1007230	Bistri??a-N??s??ud	Bistrita-Nasaud	1002490	\N	Jurisdiction	\N
1007259	Orenburg	Orenburg	1002491	\N	Jurisdiction	\N
1007279	Kabardino-Balkariya	Kabardino-Balkariya	1002491	\N	Jurisdiction	\N
1007296	Khanty-Mansiyskiy Avtonomnyy Okrug	Khanty-Mansiyskiy Avtonomnyy Okrug	1002491	\N	Jurisdiction	\N
1007317	Northern Province	Northern Province	1002492	\N	Jurisdiction	\N
1007336	Central Darfur	Central Darfur	1002520	\N	Jurisdiction	\N
1007344	Northern State	Northern State	1002520	\N	Jurisdiction	\N
1007367	J??mtland	Jamtland	1002524	\N	Jurisdiction	\N
1007383	Koper-Capodistria	Koper-Capodistria	1002511	\N	Jurisdiction	\N
1007409	Louga	Louga	1002504	\N	Jurisdiction	\N
1007420	Woqooyi Galbeed	Woqooyi Galbeed	1002513	\N	Jurisdiction	\N
1007432	Central Equatoria	Central Equatoria	1002517	\N	Jurisdiction	\N
1007461	Daraa	Daraa	1002526	\N	Jurisdiction	\N
1007474	Ouadda??	Ouaddai	1002353	\N	Jurisdiction	\N
1007491	Plateaux	Plateaux	1002531	\N	Jurisdiction	\N
1007511	Nakhon Sawan	Nakhon Sawan	1002530	\N	Jurisdiction	\N
1007526	Changwat Ubon Ratchathani	Changwat Ubon Ratchathani	1002530	\N	Jurisdiction	\N
1007555	Phatthalung	Phatthalung	1002530	\N	Jurisdiction	\N
1007578	Baucau	Baucau	1002372	\N	Jurisdiction	\N
1000098	Wrongful termination	Wrongful termination	1000026	\N	PracticeGroup	\N
1000099	Alternative energy	Alternative energy	1000027	\N	PracticeGroup	\N
1000100	Nuclear	Nuclear	1000027	\N	PracticeGroup	\N
1000101	Oil and gas	Oil and gas	1000027	\N	PracticeGroup	\N
1000103	Cleanup	Cleanup	1000029	\N	PracticeGroup	\N
1000108	Immigration	Immigration	1000031	\N	PracticeGroup	\N
1000109	Matrimonial	Matrimonial	1000031	\N	PracticeGroup	\N
1000110	Parental	Parental	1000031	\N	PracticeGroup	\N
1000111	Commercial finance	Commercial finance	1000032	\N	PracticeGroup	\N
1000112	Debt Capital markets	Debt Capital markets	1000032	\N	PracticeGroup	\N
1000113	Project finance	Project finance	1000032	\N	PracticeGroup	\N
1000114	Public finance	Public finance	1000032	\N	PracticeGroup	\N
1000115	Structured finance	Structured finance	1000032	\N	PracticeGroup	\N
1000116	Cybersecurity	Cybersecurity	1000036	\N	PracticeGroup	\N
1000117	Government access	Government access	1000036	\N	PracticeGroup	\N
1000118	Privacy	Privacy	1000036	\N	PracticeGroup	\N
1000119	Copyright	Copyright	1000038	\N	PracticeGroup	\N
1000120	Patent	Patent	1000038	\N	PracticeGroup	\N
1000121	Trade secrets	Trade secrets	1000038	\N	PracticeGroup	\N
1000122	Trademark	Trademark	1000038	\N	PracticeGroup	\N
1000123	Maritime	Maritime	1000039	\N	PracticeGroup	\N
1000124	Private international	Private international	1000039	\N	PracticeGroup	\N
1000125	Public international	Public international	1000039	\N	PracticeGroup	\N
1000126	Assault	Assault	1000040	\N	PracticeGroup	\N
1000127	Defamation	Defamation	1000040	\N	PracticeGroup	\N
1000128	Negligence	Negligence	1000040	\N	PracticeGroup	\N
1000129	Construction	Construction	1000043	\N	PracticeGroup	\N
1000130	Eminent domain	Eminent domain	1000043	\N	PracticeGroup	\N
1000131	Land use and zoning	Land use and zoning	1000043	\N	PracticeGroup	\N
1000132	Leases	Leases	1000043	\N	PracticeGroup	\N
1000133	Mortgages	Mortgages	1000043	\N	PracticeGroup	\N
1000135	Compliance	Compliance	1000044	\N	PracticeGroup	\N
1000136	Lobbying	Lobbying	1000044	\N	PracticeGroup	\N
1000137	Commodities	Commodities	1000046	\N	PracticeGroup	\N
1005952	A??n Temouchent	Ain Temouchent	1002315	\N	Jurisdiction	\N
1008021	Communication services	Communication services	\N	\N	Sector	\N
1008022	Consumer discretionary	Consumer discretionary	\N	\N	Sector	\N
1008023	Consumer staples	Consumer staples	\N	\N	Sector	\N
1008025	Financials	Financials	\N	\N	Sector	\N
1008026	Healthcare	Healthcare	\N	\N	Sector	\N
1008027	Industrials	Industrials	\N	\N	Sector	\N
1008028	Information technology	Information technology	\N	\N	Sector	\N
1008029	Materials	Materials	\N	\N	Sector	\N
1008030	Real estate	Real estate	\N	\N	Sector	\N
1008031	Utilities	Utilities	\N	\N	Sector	\N
1008032	Media & Entertainment	Media & Entertainment	1008021	\N	Sector	\N
1008033	Telecommunication Services	Telecommunication Services	1008021	\N	Sector	\N
1008034	Automobile and components	Automobile and components	1008022	\N	Sector	\N
1008035	Consumer durables and apparels	Consumer durables and apparels	1008022	\N	Sector	\N
1008036	Consumer services	Consumer services	1008022	\N	Sector	\N
1008037	Retailing	Retailing	1008022	\N	Sector	\N
1008038	Food and staples retailing	Food and staples retailing	1008023	\N	Sector	\N
1008039	Food, beverage and tobacco	Food, beverage and tobacco	1008023	\N	Sector	\N
1008040	Household and personal products	Household and personal products	1008023	\N	Sector	\N
1008041	Energy	Energy	1008024	\N	Sector	\N
1008042	Banks	Banks	1008025	\N	Sector	\N
1008043	Diversified financials	Diversified financials	1008025	\N	Sector	\N
1008044	Insurance	Insurance	1008025	\N	Sector	\N
1008045	Health care equipment and services	Health care equipment and services	1008026	\N	Sector	\N
1008046	Pharmaceuticals, biotechnology and life sciences	Pharmaceuticals, biotechnology and life sciences	1008026	\N	Sector	\N
1008047	Capital goods	Capital goods	1008027	\N	Sector	\N
1008048	Commercial and professional services	Commercial and professional services	1008027	\N	Sector	\N
1008049	Transportation	Transportation	1008027	\N	Sector	\N
1008050	Semiconductors & Semiconductor Equipment 	Semiconductors & Semiconductor Equipment 	1008028	\N	Sector	\N
1008051	Software and services	Software and services	1008028	\N	Sector	\N
1008052	Technology hardware and equipment	Technology hardware and equipment	1008028	\N	Sector	\N
1008053	Materials	Materials	1008029	\N	Sector	\N
1008054	Real estate	Real estate	1008030	\N	Sector	\N
1008055	Utilities	Utilities	1008031	\N	Sector	\N
1008117	Entertainment	Entertainment	1008032	\N	Sector	\N
1008118	Interactive media and services	Interactive media and services	1008032	\N	Sector	\N
1008116	Media	Media	1008032	\N	Sector	\N
1008114	Diversified Telecommunication Services	Diversified Telecommunication Services	1008033	\N	Sector	\N
1008115	Wireless Telecommunication Services	Wireless Telecommunication Services	1008033	\N	Sector	\N
1008078	Auto components	Auto components	1008034	\N	Sector	\N
1008079	Automobiles	Automobiles	1008034	\N	Sector	\N
1008080	Household durables	Household durables	1008035	\N	Sector	\N
1007592	N??bul	Nabul	1002534	\N	Jurisdiction	\N
1007607	B??jah	Bajah	1002534	\N	Jurisdiction	\N
1007625	??zmir	Izmir	1002535	\N	Jurisdiction	\N
1007642	Afyonkarahisar	Afyonkarahisar	1002535	\N	Jurisdiction	\N
1007660	??anakkale Province	Canakkale Province	1002535	\N	Jurisdiction	\N
1005340	Andorra la Vella	Andorra la Vella	1002317	\N	Jurisdiction	\N
1005346	Abu Dhabi	Abu Dhabi	1002542	\N	Jurisdiction	\N
1005351	Jowzj??n	Jowzjan	1002312	\N	Jurisdiction	\N
1005356	Wil??yat-e Baghl??n	Wilayat-e Baghlan	1002312	\N	Jurisdiction	\N
1005478	Sumqayit	Sumqayit	1002326	\N	Jurisdiction	\N
1005482	Sabirabad	Sabirabad	1002326	\N	Jurisdiction	\N
1005487	Ming??cevir	Ming??cevir	1002326	\N	Jurisdiction	\N
1005494	A??su	Agsu	1002326	\N	Jurisdiction	\N
1005500	Saint Michael	Saint Michael	1002330	\N	Jurisdiction	\N
1005505	R??jsh??hi	Rajshahi	1002329	\N	Jurisdiction	\N
1005511	Plateau-Central	Plateau-Central	1002345	\N	Jurisdiction	\N
1005519	High-Basins	High-Basins	1002345	\N	Jurisdiction	\N
1005526	Vidin	Vidin	1002344	\N	Jurisdiction	\N
1005530	T??rgovishte	Turgovishte	1002344	\N	Jurisdiction	\N
1005538	Sliven	Sliven	1002344	\N	Jurisdiction	\N
1005543	Sofiya	Sofiya	1002344	\N	Jurisdiction	\N
1005549	Montana	Montana	1002344	\N	Jurisdiction	\N
1005554	Central Governorate	Central Governorate	1002328	\N	Jurisdiction	\N
1005565	Rutana	Rutana	1002346	\N	Jurisdiction	\N
1005570	Qu??m??	Queme	1002334	\N	Jurisdiction	\N
1005577	Littoral	Littoral	1002334	\N	Jurisdiction	\N
1005583	Santa Cruz	Santa Cruz	1002337	\N	Jurisdiction	\N
1005589	La Paz	La Paz	1002337	\N	Jurisdiction	\N
1005593	Pernambuco	Pernambuco	1002341	\N	Jurisdiction	\N
1005602	Amazonas	Amazonas	1002341	\N	Jurisdiction	\N
1005607	Esp??rito Santo	Espirito Santo	1002341	\N	Jurisdiction	\N
1005615	Federal District	Federal District	1002341	\N	Jurisdiction	\N
1005622	Punakha	Punakha	1002336	\N	Jurisdiction	\N
1005628	Southern	Southern	1002340	\N	Jurisdiction	\N
1005636	Brest	Brest	1002331	\N	Jurisdiction	\N
1005641	Belize	Belize	1002333	\N	Jurisdiction	\N
1005646	Manitoba	Manitoba	1002349	\N	Jurisdiction	\N
1008081	Leisure products	Leisure products	1008035	\N	Sector	\N
1005651	Saskatchewan	Saskatchewan	1002349	\N	Jurisdiction	\N
1005656	Kasa??-Occidental	Kasai-Occidental	1002367	\N	Jurisdiction	\N
1005664	Kinshasa	Kinshasa	1002367	\N	Jurisdiction	\N
1005671	Sangha-Mba??r??	Sangha-Mbaere	1002352	\N	Jurisdiction	\N
1005678	Bangui	Bangui	1002352	\N	Jurisdiction	\N
1005684	Bouenza	Bouenza	1002488	\N	Jurisdiction	\N
1005689	Zug	Zug	1002525	\N	Jurisdiction	\N
1005696	Schaffhausen	Schaffhausen	1002525	\N	Jurisdiction	\N
1005703	Appenzell Ausserrhoden	Appenzell Ausserrhoden	1002525	\N	Jurisdiction	\N
1005710	Bafing	Bafing	1002417	\N	Jurisdiction	\N
1005715	Vall??e du Bandama	Vallee du Bandama	1002417	\N	Jurisdiction	\N
1005722	N??zi-Como??	N??zi-Comoe	1002417	\N	Jurisdiction	\N
1000083	Criminal proceedings	Criminal proceedings	1000025	\N	PracticeGroup	\N
1000085	Insolvency	Insolvency	1000025	\N	PracticeGroup	\N
1000086	Investigations	Investigations	1000025	\N	PracticeGroup	\N
1000087	Small claims	Small claims	1000025	\N	PracticeGroup	\N
1000088	Compensation and benefits	Compensation and benefits	1000026	\N	PracticeGroup	\N
1000089	Diability	Diability	1000026	\N	PracticeGroup	\N
1000090	Discrimination	Discrimination	1000026	\N	PracticeGroup	\N
1000091	Employee misconduct	Employee misconduct	1000026	\N	PracticeGroup	\N
1000092	Immigration	Immigration	1000026	\N	PracticeGroup	\N
1000093	Medical leave	Medical leave	1000026	\N	PracticeGroup	\N
1000094	OSHA	OSHA	1000026	\N	PracticeGroup	\N
1000095	Union relations and negotiations	Union relations and negotiations	1000026	\N	PracticeGroup	\N
1000096	Whistleblower	Whistleblower	1000026	\N	PracticeGroup	\N
1000097	Workers compensation	Workers compensation	1000026	\N	PracticeGroup	\N
1000139	Exchanges	Exchanges	1000046	\N	PracticeGroup	\N
1000140	Investment advisory and dealings	Investment advisory and dealings	1000046	\N	PracticeGroup	\N
1000141	Investment entities and funds	Investment entities and funds	1000046	\N	PracticeGroup	\N
1000142	Direct taxes	Direct taxes	1000048	\N	PracticeGroup	\N
1000143	Indirect taxes	Indirect taxes	1000048	\N	PracticeGroup	\N
1000144	Non-profit	Non-profit	1000048	\N	PracticeGroup	\N
1005956	El Bayadh	El Bayadh	1002315	\N	Jurisdiction	\N
1005957	B??char	Bechar	1002315	\N	Jurisdiction	\N
1005958	Naama ??????????????	Naama ??????????????	1002315	\N	Jurisdiction	\N
1005963	Napo	Napo	1002373	\N	Jurisdiction	\N
1005965	Santo Domingo de los Ts??chilas	Santo Domingo de los Tsachilas	1002373	\N	Jurisdiction	\N
1005972	Cotopaxi	Cotopaxi	1002373	\N	Jurisdiction	\N
1005975	Imbabura	Imbabura	1002373	\N	Jurisdiction	\N
1005979	Sucumbios	Sucumbios	1002373	\N	Jurisdiction	\N
1005983	Tartu	Tartu	1002378	\N	Jurisdiction	\N
1005986	L????ne-Virumaa	Laane-Virumaa	1002378	\N	Jurisdiction	\N
1005989	Mu?????faz??at al Qaly??b??yah	Muhafaz??at al Qalyubiyah	1002374	\N	Jurisdiction	\N
1005996	Al Miny??	Al Minya	1002374	\N	Jurisdiction	\N
1006000	Eastern Province	Eastern Province	1002374	\N	Jurisdiction	\N
1006005	Cairo Governorate	Cairo Governorate	1002374	\N	Jurisdiction	\N
1006008	Al Ism???????l??yah	Al Isma'iliyah	1002374	\N	Jurisdiction	\N
1006013	Sham??l S??n????	Shamal Sina??	1002374	\N	Jurisdiction	\N
1006018	Ma????kel	Ma??akel	1002377	\N	Jurisdiction	\N
1005730	Antofagasta	Antofagasta	1002354	\N	Jurisdiction	\N
1005735	Los Lagos	Los Lagos	1002354	\N	Jurisdiction	\N
1005742	North-West Province	North-West Province	1002348	\N	Jurisdiction	\N
1005748	Littoral	Littoral	1002348	\N	Jurisdiction	\N
1005753	Guizhou Sheng	Guizhou Sheng	1002355	\N	Jurisdiction	\N
1005768	Shanxi Sheng	Shanxi Sheng	1002355	\N	Jurisdiction	\N
1005774	Tianjin Shi	Tianjin Shi	1002355	\N	Jurisdiction	\N
1005780	Heilongjiang Sheng	Heilongjiang Sheng	1002355	\N	Jurisdiction	\N
1005786	Meta	Meta	1002358	\N	Jurisdiction	\N
1005790	Bol??var	Bolivar	1002358	\N	Jurisdiction	\N
1005797	Santander	Santander	1002358	\N	Jurisdiction	\N
1005804	Putumayo	Putumayo	1002358	\N	Jurisdiction	\N
1005808	Caquet??	Caqueta	1002358	\N	Jurisdiction	\N
1005815	Heredia	Heredia	1002361	\N	Jurisdiction	\N
1005819	Sancti Sp??ritus	Sancti Spiritus	1002363	\N	Jurisdiction	\N
1005828	Mayabeque	Mayabeque	1002363	\N	Jurisdiction	\N
1005835	Praia	Praia	1002350	\N	Jurisdiction	\N
1005840	Lefkosia	Lefkosia	1002365	\N	Jurisdiction	\N
1005845	South Moravian	South Moravian	1002366	\N	Jurisdiction	\N
1005853	Karlovarsk??	Karlovarsky	1002366	\N	Jurisdiction	\N
1005860	North Rhine-Westphalia	North Rhine-Westphalia	1002391	\N	Jurisdiction	\N
1005868	Hamburg	Hamburg	1002391	\N	Jurisdiction	\N
1005873	Bremen	Bremen	1002391	\N	Jurisdiction	\N
1005879	South Denmark	South Denmark	1002368	\N	Jurisdiction	\N
1005886	San Crist??bal	San Cristobal	1002371	\N	Jurisdiction	\N
1005891	San Jos?? de Ocoa	San Jose de Ocoa	1002371	\N	Jurisdiction	\N
1005900	Mar??a Trinidad S??nchez	Maria Trinidad Sanchez	1002371	\N	Jurisdiction	\N
1005907	S??nchez Ram??rez	Sanchez Ramirez	1002371	\N	Jurisdiction	\N
1005915	Relizane	Relizane	1002315	\N	Jurisdiction	\N
1005922	Beja??a	Bejaia	1002315	\N	Jurisdiction	\N
1005923	Tiaret	Tiaret	1002315	\N	Jurisdiction	\N
1005929	Skikda	Skikda	1002315	\N	Jurisdiction	\N
1005936	Chlef	Chlef	1002315	\N	Jurisdiction	\N
1005941	El Oued	El Oued	1002315	\N	Jurisdiction	\N
1005946	Djelfa	Djelfa	1002315	\N	Jurisdiction	\N
1005951	Guelma	Guelma	1002315	\N	Jurisdiction	\N
1005959	Zamora-Chinchipe	Zamora-Chinchipe	1002373	\N	Jurisdiction	\N
1005967	Santa Elena	Santa Elena	1002373	\N	Jurisdiction	\N
1005971	Pastaza	Pastaza	1002373	\N	Jurisdiction	\N
1005978	Ca??ar	Canar	1002373	\N	Jurisdiction	\N
1005982	Viljandimaa	Viljandimaa	1002378	\N	Jurisdiction	\N
1005988	Mu?????faz??at al Gharb??yah	Muhafaz??at al Gharbiyah	1002374	\N	Jurisdiction	\N
1007026	Southland	Southland	1002465	\N	Jurisdiction	\N
1006001	Mu?????faz??at Ma??r?????	Muhafaz??at Matruh	1002374	\N	Jurisdiction	\N
1006007	Mu?????faz??at B??r Sa?????d	Muhafaz??at Bur Sa'id	1002374	\N	Jurisdiction	\N
1006017	Gash Barka	Gash Barka	1002377	\N	Jurisdiction	\N
1006024	Valencia	Valencia	1002518	\N	Jurisdiction	\N
1006029	Basque Country	Basque Country	1002518	\N	Jurisdiction	\N
1006036	Cantabria	Cantabria	1002518	\N	Jurisdiction	\N
1006043	Tigray	Tigray	1002379	\N	Jurisdiction	\N
1006047	??far	Afar	1002379	\N	Jurisdiction	\N
1006052	Uusimaa	Uusimaa	1002383	\N	Jurisdiction	\N
1006057	Southern Ostrobothnia	Southern Ostrobothnia	1002383	\N	Jurisdiction	\N
1006061	Northern Ostrobothnia	Northern Ostrobothnia	1002383	\N	Jurisdiction	\N
1006064	P??ij??nne Tavastia	Paijanne Tavastia	1002383	\N	Jurisdiction	\N
1006071	Northern	Northern	1002382	\N	Jurisdiction	\N
1006076	Nord-Pas-de-Calais-Picardie	Nord-Pas-de-Calais-Picardie	1002384	\N	Jurisdiction	\N
1006088	Ogoou??-Maritime	Ogooue-Maritime	1002388	\N	Jurisdiction	\N
1006094	Ogoou??-Lolo	Ogooue-Lolo	1002388	\N	Jurisdiction	\N
1006102	Shida Kartli	Shida Kartli	1002390	\N	Jurisdiction	\N
1006108	Ajaria	Ajaria	1002390	\N	Jurisdiction	\N
1006113	Central	Central	1002392	\N	Jurisdiction	\N
1006118	Ashanti	Ashanti	1002392	\N	Jurisdiction	\N
1006124	North Bank	North Bank	1002389	\N	Jurisdiction	\N
1006129	Mamou	Mamou	1002401	\N	Jurisdiction	\N
1006135	Ki??-Ntem	Kie-Ntem	1002376	\N	Jurisdiction	\N
1006141	Central Greece	Central Greece	1002394	\N	Jurisdiction	\N
1006148	East Macedonia and Thrace	East Macedonia and Thrace	1002394	\N	Jurisdiction	\N
1006155	Sacatep??quez	Sacatepequez	1002399	\N	Jurisdiction	\N
1006163	El Progreso	El Progreso	1002399	\N	Jurisdiction	\N
1006170	Huehuetenango	Huehuetenango	1002399	\N	Jurisdiction	\N
1006178	Bissau	Bissau	1002402	\N	Jurisdiction	\N
1006181	Upper Demerara-Berbice	Upper Demerara-Berbice	1002403	\N	Jurisdiction	\N
1006191	Yoro	Yoro	1002405	\N	Jurisdiction	\N
1006196	Cop??n	Copan	1002405	\N	Jurisdiction	\N
1006202	Choluteca	Choluteca	1002405	\N	Jurisdiction	\N
1006203	Zagreba??ka	Zagrebacka	1002362	\N	Jurisdiction	\N
1006206	Vukovarsko-Srijemska	Vukovarsko-Srijemska	1002362	\N	Jurisdiction	\N
1006215	Istarska	Istarska	1002362	\N	Jurisdiction	\N
1006221	Bjelovarsko-Bilogorska	Bjelovarsko-Bilogorska	1002362	\N	Jurisdiction	\N
1006228	Sud-Est	Sud-Est	1002404	\N	Jurisdiction	\N
1006235	Hajd??-Bihar	Hajdu-Bihar	1002407	\N	Jurisdiction	\N
1006243	Tolna	Tolna	1002407	\N	Jurisdiction	\N
1006248	Baranya	Baranya	1002407	\N	Jurisdiction	\N
1006250	Budapest	Budapest	1002407	\N	Jurisdiction	\N
1006257	South Sulawesi	South Sulawesi	1002410	\N	Jurisdiction	\N
1006263	Lampung	Lampung	1002410	\N	Jurisdiction	\N
1006270	Jambi	Jambi	1002410	\N	Jurisdiction	\N
1006274	Central Kalimantan	Central Kalimantan	1002410	\N	Jurisdiction	\N
1006280	South Kalimantan	South Kalimantan	1002410	\N	Jurisdiction	\N
1006289	Jerusalem	Jerusalem	1002415	\N	Jurisdiction	\N
1006295	Douglas	Douglas	1002414	\N	Jurisdiction	\N
1006300	Telangana	Telangana	1002409	\N	Jurisdiction	\N
1006308	Gujarat	Gujarat	1002409	\N	Jurisdiction	\N
1006313	Chhattisgarh	Chhattisgarh	1002409	\N	Jurisdiction	\N
1006319	Manipur	Manipur	1002409	\N	Jurisdiction	\N
1006325	Pondicherry	Pondicherry	1002409	\N	Jurisdiction	\N
1006331	Dah??k	Dahuk	1002412	\N	Jurisdiction	\N
1006336	Arb??l	Arbil	1002412	\N	Jurisdiction	\N
1006341	As Sulaym??n??yah	As Sulaymaniyah	1002412	\N	Jurisdiction	\N
1006345	Al Q??dis??yah	Al Qadisiyah	1002412	\N	Jurisdiction	\N
1006347	An Najaf	An Najaf	1002412	\N	Jurisdiction	\N
1006354	Zanjan	Zanjan	1002411	\N	Jurisdiction	\N
1006359	Razavi Khorasan	Razavi Khorasan	1002411	\N	Jurisdiction	\N
1006366	Khor??s??n-e Shom??l??	Khorasan-e Shomali	1002411	\N	Jurisdiction	\N
1006373	Hormozgan	Hormozgan	1002411	\N	Jurisdiction	\N
1006380	Northeast	Northeast	1002408	\N	Jurisdiction	\N
1006383	Calabria	Calabria	1002416	\N	Jurisdiction	\N
1006390	Campania	Campania	1002416	\N	Jurisdiction	\N
1006396	Trentino-Alto Adige	Trentino-Alto Adige	1002416	\N	Jurisdiction	\N
1006403	Saint Catherine	Saint Catherine	1002418	\N	Jurisdiction	\N
1006410	Amman	Amman	1002421	\N	Jurisdiction	\N
1006415	Karak	Karak	1002421	\N	Jurisdiction	\N
1006423	Kanagawa	Kanagawa	1002419	\N	Jurisdiction	\N
1006428	Ibaraki	Ibaraki	1002419	\N	Jurisdiction	\N
1006435	Kyoto	Kyoto	1002419	\N	Jurisdiction	\N
1006440	Yamaguchi	Yamaguchi	1002419	\N	Jurisdiction	\N
1006446	Tokyo	Tokyo	1002419	\N	Jurisdiction	\N
1006451	Ishikawa	Ishikawa	1002419	\N	Jurisdiction	\N
1006458	Akita	Akita	1002419	\N	Jurisdiction	\N
1006463	Ehime	Ehime	1002419	\N	Jurisdiction	\N
1006469	Bungoma	Bungoma	1002423	\N	Jurisdiction	\N
1006476	Narok	Narok	1002423	\N	Jurisdiction	\N
1006481	Migori	Migori	1002423	\N	Jurisdiction	\N
1006488	Machakos	Machakos	1002423	\N	Jurisdiction	\N
1006493	Trans Nzoia	Trans Nzoia	1002423	\N	Jurisdiction	\N
1002313	Aland Islands	Aland Islands	\N	\N	Jurisdiction	\N
1002315	Algeria	Algeria	\N	\N	Jurisdiction	\N
1002316	American Samoa	American Samoa	\N	\N	Jurisdiction	\N
1002317	Andorra	Andorra	\N	\N	Jurisdiction	\N
1002319	Anguilla	Anguilla	\N	\N	Jurisdiction	\N
1002321	Argentina	Argentina	\N	\N	Jurisdiction	\N
1002322	Armenia	Armenia	\N	\N	Jurisdiction	\N
1002323	Aruba	Aruba	\N	\N	Jurisdiction	\N
1002324	Australia	Australia	\N	\N	Jurisdiction	\N
1002325	Austria	Austria	\N	\N	Jurisdiction	\N
1002327	Bahamas	Bahamas	\N	\N	Jurisdiction	\N
1002328	Bahrain	Bahrain	\N	\N	Jurisdiction	\N
1002330	Barbados	Barbados	\N	\N	Jurisdiction	\N
1002331	Belarus	Belarus	\N	\N	Jurisdiction	\N
1002332	Belgium	Belgium	\N	\N	Jurisdiction	\N
1002334	Benin	Benin	\N	\N	Jurisdiction	\N
1002335	Bermuda	Bermuda	\N	\N	Jurisdiction	\N
1002336	Bhutan	Bhutan	\N	\N	Jurisdiction	\N
1002339	Bosnia and Herzegovina	Bosnia and Herzegovina	\N	\N	Jurisdiction	\N
1002340	Botswana	Botswana	\N	\N	Jurisdiction	\N
1002341	Brazil	Brazil	\N	\N	Jurisdiction	\N
1002342	British Virgin Islands	British Virgin Islands	\N	\N	Jurisdiction	\N
1002343	Brunei	Brunei	\N	\N	Jurisdiction	\N
1006496	Kirinyaga	Kirinyaga	1002423	\N	Jurisdiction	\N
1006500	Baringo	Baringo	1002423	\N	Jurisdiction	\N
1006506	Siaya	Siaya	1002423	\N	Jurisdiction	\N
1006512	Talas	Talas	1002427	\N	Jurisdiction	\N
1006517	Phnom Penh	Phnom Penh	1002347	\N	Jurisdiction	\N
1006213	??ibensko-Kniniska	Sibensko-Kniniska	1002362	\N	Jurisdiction	\N
1006529	Ratanakiri	Ratanakiri	1002347	\N	Jurisdiction	\N
1006535	Preah Sihanouk	Preah Sihanouk	1002347	\N	Jurisdiction	\N
1006541	Grande Comore	Grande Comore	1002359	\N	Jurisdiction	\N
1006548	Hamgy??ng-namdo	Hamgyong-namdo	1002471	\N	Jurisdiction	\N
1006554	Gyeongsangbuk-do	Gyeongsangbuk-do	1002516	\N	Jurisdiction	\N
1006563	Daejeon	Daejeon	1002516	\N	Jurisdiction	\N
1006569	Jeju-do	Jeju-do	1002516	\N	Jurisdiction	\N
1006574	Al Jahr????	Al Jahra??	1002426	\N	Jurisdiction	\N
1006581	Qaraghandy	Qaraghandy	1002422	\N	Jurisdiction	\N
1006586	Ongt??stik Qazaqstan	Ongtustik Qazaqstan	1002422	\N	Jurisdiction	\N
1006592	Astana Qalasy	Astana Qalasy	1002422	\N	Jurisdiction	\N
1006599	Vientiane Province	Vientiane Province	1002428	\N	Jurisdiction	\N
1006607	Liban-Sud	Liban-Sud	1002430	\N	Jurisdiction	\N
1006612	Castries Quarter	Castries Quarter	1002496	\N	Jurisdiction	\N
1006622	North Central	North Central	1002519	\N	Jurisdiction	\N
1006629	Sinoe	Sinoe	1002432	\N	Jurisdiction	\N
1006636	Leribe	Leribe	1002431	\N	Jurisdiction	\N
1006638	Butha-Buthe	Butha-Buthe	1002431	\N	Jurisdiction	\N
1006640	Vilnius County	Vilnius County	1002435	\N	Jurisdiction	\N
1006646	Marijampol??s apskritis	Marijampoles apskritis	1002435	\N	Jurisdiction	\N
1006652	Liep??ja	Liepaja	1002429	\N	Jurisdiction	\N
1006659	Jelgava	Jelgava	1002429	\N	Jurisdiction	\N
1006663	Sha???b??yat al Bu??n??n	Sha'biyat al Butnan	1002433	\N	Jurisdiction	\N
1006672	Sha???b??yat al Jabal al Gharb??	Sha'biyat al Jabal al Gharbi	1002433	\N	Jurisdiction	\N
1006681	Sha???b??yat Gh??t	Sha'biyat Ghat	1002433	\N	Jurisdiction	\N
1006686	Doukkala-Abda	Doukkala-Abda	1002457	\N	Jurisdiction	\N
1006691	Gharb-Chrarda-Beni Hssen	Gharb-Chrarda-Beni Hssen	1002457	\N	Jurisdiction	\N
1006701	St??nga Nistrului	Stinga Nistrului	1002452	\N	Jurisdiction	\N
1006709	Telene??ti	Telenesti	1002452	\N	Jurisdiction	\N
1006715	B??l??i	Balti	1002452	\N	Jurisdiction	\N
1006722	Bijelo Polje	Bijelo Polje	1002455	\N	Jurisdiction	\N
1006729	Betsiboka	Betsiboka	1002439	\N	Jurisdiction	\N
1006733	Vakinankaratra	Vakinankaratra	1002439	\N	Jurisdiction	\N
1006739	Alaotra Mangoro	Alaotra Mangoro	1002439	\N	Jurisdiction	\N
1006749	Veles	Veles	1002438	\N	Jurisdiction	\N
1006754	Struga	Struga	1002438	\N	Jurisdiction	\N
1006761	Ohrid	Ohrid	1002438	\N	Jurisdiction	\N
1006765	Kumanovo	Kumanovo	1002438	\N	Jurisdiction	\N
1006772	Gevgelija	Gevgelija	1002438	\N	Jurisdiction	\N
1007593	Kef	Kef	1002534	\N	Jurisdiction	\N
1006780	Ilinden	Ilinden	1002438	\N	Jurisdiction	\N
1006787	Mopti	Mopti	1002443	\N	Jurisdiction	\N
1006792	Ayeyarwady	Ayeyarwady	1002459	\N	Jurisdiction	\N
1006798	Shan	Shan	1002459	\N	Jurisdiction	\N
1006805	Dzabkhan	Dzabkhan	1002454	\N	Jurisdiction	\N
1006810	Ulaanbaatar	Ulaanbaatar	1002454	\N	Jurisdiction	\N
1006817	??mn??gov??	Omnogovi	1002454	\N	Jurisdiction	\N
1006823	Macau	Macau	1002437	\N	Jurisdiction	\N
1006828	Guidimaka	Guidimaka	1002447	\N	Jurisdiction	\N
1006834	Adrar	Adrar	1002447	\N	Jurisdiction	\N
1006840	Qormi	Qormi	1002444	\N	Jurisdiction	\N
1006846	Port Louis	Port Louis	1002448	\N	Jurisdiction	\N
1006851	Northern Region	Northern Region	1002440	\N	Jurisdiction	\N
1006857	Hidalgo	Hidalgo	1002450	\N	Jurisdiction	\N
1002530	Thailand	Thailand	\N	\N	Jurisdiction	\N
1002531	Togo	Togo	\N	\N	Jurisdiction	\N
1002532	Tonga	Tonga	\N	\N	Jurisdiction	\N
1002534	Tunisia	Tunisia	\N	\N	Jurisdiction	\N
1002535	Turkey	Turkey	\N	\N	Jurisdiction	\N
1002536	Turkmenistan	Turkmenistan	\N	\N	Jurisdiction	\N
1002538	Tuvalu	Tuvalu	\N	\N	Jurisdiction	\N
1002539	U.S. Virgin Islands	U.S. Virgin Islands	\N	\N	Jurisdiction	\N
1002540	Uganda	Uganda	\N	\N	Jurisdiction	\N
1002541	Ukraine	Ukraine	\N	\N	Jurisdiction	\N
1002543	United Kingdom	United Kingdom	\N	\N	Jurisdiction	\N
1002544	United States	United States	\N	\N	Jurisdiction	\N
1002545	Uruguay	Uruguay	\N	\N	Jurisdiction	\N
1002547	Vanuatu	Vanuatu	\N	\N	Jurisdiction	\N
1002548	Vatican	Vatican	\N	\N	Jurisdiction	\N
1002549	Venezuela	Venezuela	\N	\N	Jurisdiction	\N
1002551	Wallis and Futuna	Wallis and Futuna	\N	\N	Jurisdiction	\N
1002552	Western Sahara	Western Sahara	\N	\N	Jurisdiction	\N
1002553	Yemen	Yemen	\N	\N	Jurisdiction	\N
1002555	Zimbabwe	Zimbabwe	\N	\N	Jurisdiction	\N
1002435	Lithuania	Lithuania	\N	\N	Jurisdiction	\N
1002438	Macedonia	Macedonia	\N	\N	Jurisdiction	\N
1002442	Maldives	Maldives	\N	\N	Jurisdiction	\N
1002445	Marshall Islands	Marshall Islands	\N	\N	Jurisdiction	\N
1002453	Monaco	Monaco	\N	\N	Jurisdiction	\N
1006863	Chiapas	Chiapas	1002450	\N	Jurisdiction	\N
1002554	Zambia	Zambia	\N	\N	Jurisdiction	\N
1006869	Quintana Roo	Quintana Roo	1002450	\N	Jurisdiction	\N
1002473	Norway	Norway	\N	\N	Jurisdiction	\N
1002474	Oman	Oman	\N	\N	Jurisdiction	\N
1002475	Pakistan	Pakistan	\N	\N	Jurisdiction	\N
1002476	Palau	Palau	\N	\N	Jurisdiction	\N
1002478	Panama	Panama	\N	\N	Jurisdiction	\N
1002479	Papua New Guinea	Papua New Guinea	\N	\N	Jurisdiction	\N
1002480	Paraguay	Paraguay	\N	\N	Jurisdiction	\N
1002481	Peru	Peru	\N	\N	Jurisdiction	\N
1002483	Pitcairn	Pitcairn	\N	\N	Jurisdiction	\N
1002484	Poland	Poland	\N	\N	Jurisdiction	\N
1002485	Portugal	Portugal	\N	\N	Jurisdiction	\N
1002487	Qatar	Qatar	\N	\N	Jurisdiction	\N
1002488	Republic of the Congo	Republic of the Congo	\N	\N	Jurisdiction	\N
1002489	Reunion	Reunion	\N	\N	Jurisdiction	\N
1002491	Russia	Russia	\N	\N	Jurisdiction	\N
1002492	Rwanda	Rwanda	\N	\N	Jurisdiction	\N
1002494	Saint Helena	Saint Helena	\N	\N	Jurisdiction	\N
1002495	Saint Kitts and Nevis	Saint Kitts and Nevis	\N	\N	Jurisdiction	\N
1002496	Saint Lucia	Saint Lucia	\N	\N	Jurisdiction	\N
1002498	Saint Pierre and Miquelon	Saint Pierre and Miquelon	\N	\N	Jurisdiction	\N
1002500	Samoa	Samoa	\N	\N	Jurisdiction	\N
1002501	San Marino	San Marino	\N	\N	Jurisdiction	\N
1002502	Sao Tome and Principe	Sao Tome and Principe	\N	\N	Jurisdiction	\N
1002503	Saudi Arabia	Saudi Arabia	\N	\N	Jurisdiction	\N
1002504	Senegal	Senegal	\N	\N	Jurisdiction	\N
1002505	Serbia	Serbia	\N	\N	Jurisdiction	\N
1002506	Seychelles	Seychelles	\N	\N	Jurisdiction	\N
1002508	Singapore	Singapore	\N	\N	Jurisdiction	\N
1002509	Sint Maarten	Sint Maarten	\N	\N	Jurisdiction	\N
1002510	Slovakia	Slovakia	\N	\N	Jurisdiction	\N
1002512	Solomon Islands	Solomon Islands	\N	\N	Jurisdiction	\N
1002513	Somalia	Somalia	\N	\N	Jurisdiction	\N
1002516	South Korea	South Korea	\N	\N	Jurisdiction	\N
1002517	South Sudan	South Sudan	\N	\N	Jurisdiction	\N
1002518	Spain	Spain	\N	\N	Jurisdiction	\N
1002519	Sri Lanka	Sri Lanka	\N	\N	Jurisdiction	\N
1002520	Sudan	Sudan	\N	\N	Jurisdiction	\N
1002521	Suriname	Suriname	\N	\N	Jurisdiction	\N
1002507	Sierra Leone	Sierra Leone	\N	\N	Jurisdiction	\N
1002511	Slovenia	Slovenia	\N	\N	Jurisdiction	\N
1002514	South Africa	South Africa	\N	\N	Jurisdiction	\N
1002515	South Georgia and the South Sandwich Islands	South Georgia and the South Sandwich Islands	\N	\N	Jurisdiction	\N
1002525	Switzerland	Switzerland	\N	\N	Jurisdiction	\N
1002529	Tanzania	Tanzania	\N	\N	Jurisdiction	\N
1007716	Arusha	Arusha	1002529	\N	Jurisdiction	\N
1006876	Michoac??n	Michoacan	1002450	\N	Jurisdiction	\N
1006882	Durango	Durango	1002450	\N	Jurisdiction	\N
1006889	Selangor	Selangor	1002441	\N	Jurisdiction	\N
1006895	Negeri Sembilan	Negeri Sembilan	1002441	\N	Jurisdiction	\N
1006903	Sofala	Sofala	1002458	\N	Jurisdiction	\N
1006907	Cabo Delgado	Cabo Delgado	1002458	\N	Jurisdiction	\N
1006915	Erongo	Erongo	1002460	\N	Jurisdiction	\N
1006920	Karas	Karas	1002460	\N	Jurisdiction	\N
1006927	Niamey	Niamey	1002467	\N	Jurisdiction	\N
1006929	Dosso	Dosso	1002467	\N	Jurisdiction	\N
1006932	Niger	Niger	1002468	\N	Jurisdiction	\N
1006937	Kano	Kano	1002468	\N	Jurisdiction	\N
1006944	Anambra	Anambra	1002468	\N	Jurisdiction	\N
1006952	Gombe	Gombe	1002468	\N	Jurisdiction	\N
1006959	Ekiti	Ekiti	1002468	\N	Jurisdiction	\N
1006965	Jigawa	Jigawa	1002468	\N	Jurisdiction	\N
1006969	Madriz	Madriz	1002466	\N	Jurisdiction	\N
1006975	Atl??ntico Sur	Atlantico Sur	1002466	\N	Jurisdiction	\N
1006982	Estel??	Esteli	1002466	\N	Jurisdiction	\N
1006987	North Brabant	North Brabant	1002463	\N	Jurisdiction	\N
1006994	Zeeland	Zeeland	1002463	\N	Jurisdiction	\N
1006999	Nord-Tr??ndelag	Nord-Trondelag	1002473	\N	Jurisdiction	\N
1007006	Oppland	Oppland	1002473	\N	Jurisdiction	\N
1007011	Aust-Agder	Aust-Agder	1002473	\N	Jurisdiction	\N
1007018	Wellington	Wellington	1002465	\N	Jurisdiction	\N
1007023	Taranaki	Taranaki	1002465	\N	Jurisdiction	\N
1007033	Al Batinah North Governorate	Al Batinah North Governorate	1002474	\N	Jurisdiction	\N
1007039	Ash Sharqiyah North Governorate	Ash Sharqiyah North Governorate	1002474	\N	Jurisdiction	\N
1007050	La Libertad	La Libertad	1002481	\N	Jurisdiction	\N
1007057	Amazonas	Amazonas	1002481	\N	Jurisdiction	\N
1007063	Tacna	Tacna	1002481	\N	Jurisdiction	\N
1007068	Arequipa	Arequipa	1002481	\N	Jurisdiction	\N
1007075	??les du Vent	Iles du Vent	1002386	\N	Jurisdiction	\N
1007079	Western Highlands	Western Highlands	1002479	\N	Jurisdiction	\N
1007080	Southern Highlands	Southern Highlands	1002479	\N	Jurisdiction	\N
1007084	West New Britain	West New Britain	1002479	\N	Jurisdiction	\N
1007092	Western Visayas	Western Visayas	1002482	\N	Jurisdiction	\N
1007095	Northern Mindanao	Northern Mindanao	1002482	\N	Jurisdiction	\N
1007104	Mimaropa	Mimaropa	1002482	\N	Jurisdiction	\N
1007108	Khyber Pakhtunkhwa	Khyber Pakhtunkhwa	1002475	\N	Jurisdiction	\N
1007116	Subcarpathian Voivodeship	Subcarpathian Voivodeship	1002484	\N	Jurisdiction	\N
1007123	Kujawsko-Pomorskie	Kujawsko-Pomorskie	1002484	\N	Jurisdiction	\N
1007130	Barceloneta	Barceloneta	1002486	\N	Jurisdiction	\N
1007142	Mayaguez	Mayaguez	1002486	\N	Jurisdiction	\N
1007149	West Bank	West Bank	1002477	\N	Jurisdiction	\N
1007157	??vora	Evora	1002485	\N	Jurisdiction	\N
1007161	Vila Real	Vila Real	1002485	\N	Jurisdiction	\N
1007168	Bragan??a	Braganca	1002485	\N	Jurisdiction	\N
1007175	Alto Paran??	Alto Parana	1002480	\N	Jurisdiction	\N
1007182	Cordillera	Cordillera	1002480	\N	Jurisdiction	\N
1007187	Al Khawr	Al Khawr	1002487	\N	Jurisdiction	\N
1006231	J??sz-Nagykun-Szolnok	Jasz-Nagykun-Szolnok	1002407	\N	Jurisdiction	\N
1006253	Daerah Istimewa Yogyakarta	Daerah Istimewa Yogyakarta	1002410	\N	Jurisdiction	\N
1006281	Sulawesi Tenggara	Sulawesi Tenggara	1002410	\N	Jurisdiction	\N
1006299	Uttar Pradesh	Uttar Pradesh	1002409	\N	Jurisdiction	\N
1005760	Liaoning	Liaoning	1002355	\N	Jurisdiction	\N
1007262	Kirov	Kirov	1002491	\N	Jurisdiction	\N
1007268	Voronezj	Voronezj	1002491	\N	Jurisdiction	\N
1007274	Pskov	Pskov	1002491	\N	Jurisdiction	\N
1007280	Ingushetiya	Ingushetiya	1002491	\N	Jurisdiction	\N
1007286	Mordoviya	Mordoviya	1002491	\N	Jurisdiction	\N
1007293	Altai Krai	Altai Krai	1002491	\N	Jurisdiction	\N
1007299	Irkutsk	Irkutsk	1002491	\N	Jurisdiction	\N
1007303	Khakasiya	Khakasiya	1002491	\N	Jurisdiction	\N
1007310	Respublika Buryatiya	Respublika Buryatiya	1002491	\N	Jurisdiction	\N
1007316	Eastern Province	Eastern Province	1002492	\N	Jurisdiction	\N
1007323	Northern Borders	Northern Borders	1002503	\N	Jurisdiction	\N
1007330	???????il	Ha??il	1002503	\N	Jurisdiction	\N
1007335	English River	English River	1002506	\N	Jurisdiction	\N
1007343	River Nile	River Nile	1002520	\N	Jurisdiction	\N
1007349	West Kordofan State	West Kordofan State	1002520	\N	Jurisdiction	\N
1007356	Gotland	Gotland	1002524	\N	Jurisdiction	\N
1007362	V??stra G??taland	Vastra Gotaland	1002524	\N	Jurisdiction	\N
1007369	S??dermanland	Sodermanland	1002524	\N	Jurisdiction	\N
1007376	Trbovlje	Trbovlje	1002511	\N	Jurisdiction	\N
1007382	Kranj	Kranj	1002511	\N	Jurisdiction	\N
1007387	Ko??ick??	Kosicky	1002510	\N	Jurisdiction	\N
1007391	Trnavsk??	Trnavsky	1002510	\N	Jurisdiction	\N
1007393	Bratislavsk??	Bratislavsky	1002510	\N	Jurisdiction	\N
1007399	Ziguinchor	Ziguinchor	1002504	\N	Jurisdiction	\N
1007407	Dakar	Dakar	1002504	\N	Jurisdiction	\N
1007413	Lower Shabeelle	Lower Shabeelle	1002513	\N	Jurisdiction	\N
1007424	Galguduud	Galguduud	1002513	\N	Jurisdiction	\N
1007429	Awdal	Awdal	1002513	\N	Jurisdiction	\N
1007434	Western Bahr al Ghazal	Western Bahr al Ghazal	1002517	\N	Jurisdiction	\N
1007443	Usulut??n	Usulutan	1002375	\N	Jurisdiction	\N
1007448	Santa Ana	Santa Ana	1002375	\N	Jurisdiction	\N
1007455	Ahuachap??n	Ahuachapan	1002375	\N	Jurisdiction	\N
1007462	Deir ez-Zor	Deir ez-Zor	1002526	\N	Jurisdiction	\N
1007468	As-Suwayda	As-Suwayda	1002526	\N	Jurisdiction	\N
1007475	Moyen-Chari	Moyen-Chari	1002353	\N	Jurisdiction	\N
1007480	Logone Occidental	Logone Occidental	1002353	\N	Jurisdiction	\N
1007487	Mayo-Kebbi Est	Mayo-Kebbi Est	1002353	\N	Jurisdiction	\N
1007494	Phuket	Phuket	1002530	\N	Jurisdiction	\N
1007500	Uthai Thani	Uthai Thani	1002530	\N	Jurisdiction	\N
1005466	Bil??suvar	Bil??suvar	1002326	\N	Jurisdiction	\N
1005470	A??dam	Agdam	1002326	\N	Jurisdiction	\N
1007506	Ratchaburi	Ratchaburi	1002530	\N	Jurisdiction	\N
1007512	Chumphon	Chumphon	1002530	\N	Jurisdiction	\N
1007518	Nakhon Ratchasima	Nakhon Ratchasima	1002530	\N	Jurisdiction	\N
1007525	Phetchabun	Phetchabun	1002530	\N	Jurisdiction	\N
1007531	Trat	Trat	1002530	\N	Jurisdiction	\N
1007536	Surin	Surin	1002530	\N	Jurisdiction	\N
1007540	Sing Buri	Sing Buri	1002530	\N	Jurisdiction	\N
1007544	Sara Buri	Sara Buri	1002530	\N	Jurisdiction	\N
1007551	Prachin Buri	Prachin Buri	1002530	\N	Jurisdiction	\N
1007671	Samsun	Samsun	1002535	\N	Jurisdiction	\N
1007677	Amasya	Amasya	1002535	\N	Jurisdiction	\N
1007682	Karab??k	Karabuk	1002535	\N	Jurisdiction	\N
1007688	D??zce	Duzce	1002535	\N	Jurisdiction	\N
1007694	Tobago	Tobago	1002533	\N	Jurisdiction	\N
1007556	Chachoengsao	Chachoengsao	1002530	\N	Jurisdiction	\N
1007563	Maha Sarakham	Maha Sarakham	1002530	\N	Jurisdiction	\N
1007568	Amnat Charoen	Amnat Charoen	1002530	\N	Jurisdiction	\N
1007576	Bobonaro	Bobonaro	1002372	\N	Jurisdiction	\N
1007583	Ahal	Ahal	1002536	\N	Jurisdiction	\N
1007588	T??nis	Tunis	1002534	\N	Jurisdiction	\N
1007596	S??d?? B?? Zayd	Sidi Bu Zayd	1002534	\N	Jurisdiction	\N
1007602	Gafsa	Gafsa	1002534	\N	Jurisdiction	\N
1007608	Jund??bah	Jundubah	1002534	\N	Jurisdiction	\N
1007615	Hatay	Hatay	1002535	\N	Jurisdiction	\N
1007620	??anl??urfa	Sanliurfa	1002535	\N	Jurisdiction	\N
1007629	Antalya	Antalya	1002535	\N	Jurisdiction	\N
1007634	Bing??l	Bingol	1002535	\N	Jurisdiction	\N
1007640	Ankara	Ankara	1002535	\N	Jurisdiction	\N
1007645	Erzurum	Erzurum	1002535	\N	Jurisdiction	\N
1007652	Batman	Batman	1002535	\N	Jurisdiction	\N
1007658	Ad??yaman	Adiyaman	1002535	\N	Jurisdiction	\N
1007663	Bilecik	Bilecik	1002535	\N	Jurisdiction	\N
1007666	Istanbul	Istanbul	1002535	\N	Jurisdiction	\N
1007701	Chaguanas	Chaguanas	1002533	\N	Jurisdiction	\N
1007707	Fukien	Fukien	1002527	\N	Jurisdiction	\N
1007714	Katavi	Katavi	1002529	\N	Jurisdiction	\N
1007718	Shinyanga	Shinyanga	1002529	\N	Jurisdiction	\N
1007725	Kilimanjaro	Kilimanjaro	1002529	\N	Jurisdiction	\N
1007732	Dar es Salaam	Dar es Salaam	1002529	\N	Jurisdiction	\N
1007738	Donetsk	Donetsk	1002541	\N	Jurisdiction	\N
1007744	Zhytomyr	Zhytomyr	1002541	\N	Jurisdiction	\N
1007751	Zakarpattia	Zakarpattia	1002541	\N	Jurisdiction	\N
1007756	Luhansk	Luhansk	1002541	\N	Jurisdiction	\N
1007762	Kyiv City	Kyiv City	1002541	\N	Jurisdiction	\N
1007767	Western Region	Western Region	1002540	\N	Jurisdiction	\N
1007775	Georgia	Georgia	1002544	\N	Jurisdiction	\N
1007780	Maryland	Maryland	1002544	\N	Jurisdiction	\N
1007787	Pennsylvania	Pennsylvania	1002544	\N	Jurisdiction	\N
1007794	Maine	Maine	1002544	\N	Jurisdiction	\N
1007799	New Hampshire	New Hampshire	1002544	\N	Jurisdiction	\N
1007806	California	California	1002544	\N	Jurisdiction	\N
1007812	Alaska	Alaska	1002544	\N	Jurisdiction	\N
1007824	San Jos??	San Jose	1002545	\N	Jurisdiction	\N
1007829	Paysand??	Paysandu	1002545	\N	Jurisdiction	\N
1007836	Colonia	Colonia	1002545	\N	Jurisdiction	\N
1007844	Toshkent	Toshkent	1002546	\N	Jurisdiction	\N
1007935	B???n Tre	Ben Tre	1002550	\N	Jurisdiction	\N
1007942	Tuamasaga	Tuamasaga	1002500	\N	Jurisdiction	\N
1007947	Pristina	Pristina	1002425	\N	Jurisdiction	\N
1007954	Sanaa	Sanaa	1002553	\N	Jurisdiction	\N
1007959	Dham??r	Dhamar	1002553	\N	Jurisdiction	\N
1007962	Mu?????faz??at ???a???ramawt	Muhafaz??at Hadramawt	1002553	\N	Jurisdiction	\N
1007973	Northern Cape	Northern Cape	1002514	\N	Jurisdiction	\N
1007991	Mashonaland West	Mashonaland West	1002555	\N	Jurisdiction	\N
1007251	Murmansk	Murmansk	1002491	\N	Jurisdiction	\N
1005473	Yevlax City	Yevlax City	1002326	\N	Jurisdiction	\N
1005477	T??rt??r	T??rt??r	1002326	\N	Jurisdiction	\N
1005481	Shaki City	Shaki City	1002326	\N	Jurisdiction	\N
1005485	Hac??qabul	Haciqabul	1002326	\N	Jurisdiction	\N
1005488	K??rd??mir	Kurd??mir	1002326	\N	Jurisdiction	\N
1005492	Shabran	Shabran	1002326	\N	Jurisdiction	\N
1005496	A??cab??di	Agcab??di	1002326	\N	Jurisdiction	\N
1005497	Federation of Bosnia and Herzegovina	Federation of Bosnia and Herzegovina	1002339	\N	Jurisdiction	\N
1005506	Khulna	Khulna	1002329	\N	Jurisdiction	\N
1005509	Wallonia	Wallonia	1002332	\N	Jurisdiction	\N
1005513	Boucle du Mouhoun	Boucle du Mouhoun	1002345	\N	Jurisdiction	\N
1005518	Centre-Nord	Centre-Nord	1002345	\N	Jurisdiction	\N
1005522	Cascades	Cascades	1002345	\N	Jurisdiction	\N
1005525	Vratsa	Vratsa	1002344	\N	Jurisdiction	\N
1005528	Veliko T??rnovo	Veliko Turnovo	1002344	\N	Jurisdiction	\N
1005533	Khaskovo	Khaskovo	1002344	\N	Jurisdiction	\N
1005536	Sofia-Capital	Sofia-Capital	1002344	\N	Jurisdiction	\N
1005541	Gabrovo	Gabrovo	1002344	\N	Jurisdiction	\N
1005544	Ruse	Ruse	1002344	\N	Jurisdiction	\N
1005548	Pernik	Pernik	1002344	\N	Jurisdiction	\N
1005551	Burgas	Burgas	1002344	\N	Jurisdiction	\N
1005553	Southern Governorate	Southern Governorate	1002328	\N	Jurisdiction	\N
1005557	Bururi	Bururi	1002346	\N	Jurisdiction	\N
1007673	Ordu	Ordu	1002535	\N	Jurisdiction	\N
1007676	Tekirda??	Tekirdag	1002535	\N	Jurisdiction	\N
1007681	Sakarya	Sakarya	1002535	\N	Jurisdiction	\N
1007685	G??m????hane	Gumushane	1002535	\N	Jurisdiction	\N
1007689	??ank??r??	Cankiri	1002535	\N	Jurisdiction	\N
1007693	Tunapuna/Piarco	Tunapuna/Piarco	1002533	\N	Jurisdiction	\N
1007698	City of Port of Spain	City of Port of Spain	1002533	\N	Jurisdiction	\N
1019493	hfh	hfh	\N	\N	Party	\N
1019494	a	a	\N	\N	Party	\N
1019495	gfh	gfh	\N	\N	Party	\N
1019496	hh	hh	\N	\N	Party	\N
1019497	gfgsdggsdg	gfgsdggsdg	\N	\N	Party	\N
1019498	gfdgfdsgsd	gfdgfdsgsd	\N	\N	Party	\N
1019499	gghfd	gghfd	\N	\N	Party	\N
1005617	Rond??nia	Rondonia	1002341	\N	Jurisdiction	\N
1019591	newtag	newtag	\N	\N	Party	\N
1006049	B??nshangul Gumuz	Binshangul Gumuz	1002379	\N	Jurisdiction	\N
1019601	aaanew	aaanew	\N	\N	Party	\N
1019610	gfdgdgfdsg	gfdgdgfdsg	\N	\N	Party	\N
1006197	Santa B??rbara	Santa Barbara	1002405	\N	Jurisdiction	\N
1006872	Sonora	Sonora	1002450	\N	Jurisdiction	\N
1019613	gfdgdsgdg	gfdgdsgdg	\N	\N	Party	\N
1006883	Baja California Sur	Baja California Sur	1002450	\N	Jurisdiction	\N
1006887	Pahang	Pahang	1002441	\N	Jurisdiction	\N
1006890	Terengganu	Terengganu	1002441	\N	Jurisdiction	\N
1019615	123	123	\N	\N	Party	\N
1006894	Kelantan	Kelantan	1002441	\N	Jurisdiction	\N
1006898	Kuala Lumpur	Kuala Lumpur	1002441	\N	Jurisdiction	\N
1006901	Putrajaya	Putrajaya	1002441	\N	Jurisdiction	\N
1005358	Faryab	Faryab	1002312	\N	Jurisdiction	\N
1006880	Colima	Colima	1002450	\N	Jurisdiction	\N
1005360	Balkh	Balkh	1002312	\N	Jurisdiction	\N
1005361	Helmand	Helmand	1002312	\N	Jurisdiction	\N
1005362	Khowst	Khowst	1002312	\N	Jurisdiction	\N
1005363	Kandah??r	Kandahar	1002312	\N	Jurisdiction	\N
1005365	Parv??n	Parvan	1002312	\N	Jurisdiction	\N
1005366	Badghis	Badghis	1002312	\N	Jurisdiction	\N
1005367	Ghazn??	Ghazni	1002312	\N	Jurisdiction	\N
1005368	Paktia	Paktia	1002312	\N	Jurisdiction	\N
1005369	Badakhshan	Badakhshan	1002312	\N	Jurisdiction	\N
1005371	Lowgar	Lowgar	1002312	\N	Jurisdiction	\N
1005372	B??m????n	Bamian	1002312	\N	Jurisdiction	\N
1005373	Konar	Konar	1002312	\N	Jurisdiction	\N
1005374	Panjshir	Panjshir	1002312	\N	Jurisdiction	\N
1005376	Vlor??	Vlore	1002314	\N	Jurisdiction	\N
1005377	Kuk??s	Kukes	1002314	\N	Jurisdiction	\N
1005378	Kor????	Korce	1002314	\N	Jurisdiction	\N
1000043	Property	Property	\N	\N	PracticeGroup	\N
1005379	Gjirokast??r	Gjirokaster	1002314	\N	Jurisdiction	\N
1005380	Elbasan	Elbasan	1002314	\N	Jurisdiction	\N
1005382	Tiran??	Tirane	1002314	\N	Jurisdiction	\N
1005383	Shkod??r	Shkoder	1002314	\N	Jurisdiction	\N
1005384	Fier	Fier	1002314	\N	Jurisdiction	\N
1005385	Lezh??	Lezhe	1002314	\N	Jurisdiction	\N
1005387	Durr??s	Durres	1002314	\N	Jurisdiction	\N
1005388	Syunik Province	Syunik Province	1002322	\N	Jurisdiction	\N
1005389	Ararat Province	Ararat Province	1002322	\N	Jurisdiction	\N
1005390	Yerevan	Yerevan	1002322	\N	Jurisdiction	\N
1005392	Lori Province	Lori Province	1002322	\N	Jurisdiction	\N
1005393	Gegharkunik Province	Gegharkunik Province	1002322	\N	Jurisdiction	\N
1005394	Kotayk Province	Kotayk Province	1002322	\N	Jurisdiction	\N
1005395	Shirak Province	Shirak Province	1002322	\N	Jurisdiction	\N
1005397	Lunda Sul	Lunda Sul	1002318	\N	Jurisdiction	\N
1005398	Lunda Norte	Lunda Norte	1002318	\N	Jurisdiction	\N
1005399	Moxico	Moxico	1002318	\N	Jurisdiction	\N
1005400	U??ge	Uige	1002318	\N	Jurisdiction	\N
1005401	Zaire	Zaire	1002318	\N	Jurisdiction	\N
1005402	Cuanza Norte	Cuanza Norte	1002318	\N	Jurisdiction	\N
1005403	Malanje	Malanje	1002318	\N	Jurisdiction	\N
1005405	Bengo	Bengo	1002318	\N	Jurisdiction	\N
1005406	Cabinda	Cabinda	1002318	\N	Jurisdiction	\N
1005407	Cuanza Sul	Cuanza Sul	1002318	\N	Jurisdiction	\N
1005408	Namibe	Namibe	1002318	\N	Jurisdiction	\N
1005410	Hu??la	Huila	1002318	\N	Jurisdiction	\N
1005411	Huambo	Huambo	1002318	\N	Jurisdiction	\N
1005412	Benguela	Benguela	1002318	\N	Jurisdiction	\N
1005413	Bi??	Bie	1002318	\N	Jurisdiction	\N
1005418	Misiones	Misiones	1002321	\N	Jurisdiction	\N
1005419	Corrientes	Corrientes	1002321	\N	Jurisdiction	\N
1005422	Neuquen	Neuquen	1002321	\N	Jurisdiction	\N
1005423	Tucum??n	Tucuman	1002321	\N	Jurisdiction	\N
1005425	San Juan	San Juan	1002321	\N	Jurisdiction	\N
1005428	Chubut	Chubut	1002321	\N	Jurisdiction	\N
1005429	Santiago del Estero	Santiago del Estero	1002321	\N	Jurisdiction	\N
1005430	Salta	Salta	1002321	\N	Jurisdiction	\N
1005431	La Pampa	La Pampa	1002321	\N	Jurisdiction	\N
1005434	San Luis	San Luis	1002321	\N	Jurisdiction	\N
1005435	Catamarca	Catamarca	1002321	\N	Jurisdiction	\N
1005437	La Rioja	La Rioja	1002321	\N	Jurisdiction	\N
1005439	Carinthia	Carinthia	1002325	\N	Jurisdiction	\N
1005441	Vienna	Vienna	1002325	\N	Jurisdiction	\N
1005442	Upper Austria	Upper Austria	1002325	\N	Jurisdiction	\N
1005443	Salzburg	Salzburg	1002325	\N	Jurisdiction	\N
1005449	Queensland	Queensland	1002324	\N	Jurisdiction	\N
1005451	Victoria	Victoria	1002324	\N	Jurisdiction	\N
1005453	Tasmania	Tasmania	1002324	\N	Jurisdiction	\N
1006207	Viroviti??k-Podravska	Virovitick-Podravska	1002362	\N	Jurisdiction	\N
1005455	Mariehamns stad	Mariehamns stad	1002313	\N	Jurisdiction	\N
1005456	Xank??ndi	Xank??ndi	1002326	\N	Jurisdiction	\N
1005458	??u??a	Susa	1002326	\N	Jurisdiction	\N
1005459	Salyan	Salyan	1002326	\N	Jurisdiction	\N
1005460	Neft??ala	Neftcala	1002326	\N	Jurisdiction	\N
1005461	Nakhichevan	Nakhichevan	1002326	\N	Jurisdiction	\N
1005464	F??zuli	Fuzuli	1002326	\N	Jurisdiction	\N
1005465	Jalilabad	Jalilabad	1002326	\N	Jurisdiction	\N
1005467	Beyl??qan	Beyl??qan	1002326	\N	Jurisdiction	\N
1005468	Astara	Astara	1002326	\N	Jurisdiction	\N
1005471	Zaqatala	Zaqatala	1002326	\N	Jurisdiction	\N
1005472	Baki	Baki	1002326	\N	Jurisdiction	\N
1005474	Goygol Rayon	Goygol Rayon	1002326	\N	Jurisdiction	\N
1005475	Xa??maz	Xacmaz	1002326	\N	Jurisdiction	\N
1006906	Zamb??zia	Zambezia	1002458	\N	Jurisdiction	\N
1006909	Inhambane	Inhambane	1002458	\N	Jurisdiction	\N
1006230	Sud	Sud	1002404	\N	Jurisdiction	\N
1006913	Zambezi	Zambezi	1002460	\N	Jurisdiction	\N
1006916	Kavango East	Kavango East	1002460	\N	Jurisdiction	\N
1006921	Omaheke	Omaheke	1002460	\N	Jurisdiction	\N
1006924	Zinder	Zinder	1002467	\N	Jurisdiction	\N
1006621	Uva	Uva	1002519	\N	Jurisdiction	\N
1006928	Diffa	Diffa	1002467	\N	Jurisdiction	\N
1006931	Kebbi	Kebbi	1002468	\N	Jurisdiction	\N
1006934	Adamawa	Adamawa	1002468	\N	Jurisdiction	\N
1006938	Delta	Delta	1002468	\N	Jurisdiction	\N
1006942	Abia	Abia	1002468	\N	Jurisdiction	\N
1006201	El Para??so	El Paraiso	1002405	\N	Jurisdiction	\N
1006945	Sokoto	Sokoto	1002468	\N	Jurisdiction	\N
1006948	Oyo	Oyo	1002468	\N	Jurisdiction	\N
1006951	Rivers	Rivers	1002468	\N	Jurisdiction	\N
1006954	Plateau	Plateau	1002468	\N	Jurisdiction	\N
1006958	Kogi	Kogi	1002468	\N	Jurisdiction	\N
1006961	Borno	Borno	1002468	\N	Jurisdiction	\N
1006964	Abuja Federal Capital Territory	Abuja Federal Capital Territory	1002468	\N	Jurisdiction	\N
1006970	Chinandega	Chinandega	1002466	\N	Jurisdiction	\N
1006974	Matagalpa	Matagalpa	1002466	\N	Jurisdiction	\N
1006978	Le??n	Leon	1002466	\N	Jurisdiction	\N
1006981	Jinotega	Jinotega	1002466	\N	Jurisdiction	\N
1006985	South Holland	South Holland	1002463	\N	Jurisdiction	\N
1006989	Flevoland	Flevoland	1002463	\N	Jurisdiction	\N
1006993	Limburg	Limburg	1002463	\N	Jurisdiction	\N
1006996	S??r-Tr??ndelag	Sor-Trondelag	1002473	\N	Jurisdiction	\N
1007000	Rogaland	Rogaland	1002473	\N	Jurisdiction	\N
1007004	M??re og Romsdal	More og Romsdal	1002473	\N	Jurisdiction	\N
1007009	Hedmark	Hedmark	1002473	\N	Jurisdiction	\N
1007012	Western Region	Western Region	1002462	\N	Jurisdiction	\N
1007016	Central Region	Central Region	1002462	\N	Jurisdiction	\N
1007021	Waikato	Waikato	1002465	\N	Jurisdiction	\N
1007249	Nizjnij Novgorod	Nizjnij Novgorod	1002491	\N	Jurisdiction	\N
1007638	Siirt	Siirt	1002535	\N	Jurisdiction	\N
1005450	Northern Territory	Northern Territory	1002324	\N	Jurisdiction	\N
1005599	Rio Grande do Norte	Rio Grande do Norte	1002341	\N	Jurisdiction	\N
1005476	Ucar	Ucar	1002326	\N	Jurisdiction	\N
1005632	Minsk	Minsk	1002331	\N	Jurisdiction	\N
1005633	Gomel	Gomel	1002331	\N	Jurisdiction	\N
1006167	Izabal	Izabal	1002399	\N	Jurisdiction	\N
1006301	Maharashtra	Maharashtra	1002409	\N	Jurisdiction	\N
1006941	Edo	Edo	1002468	\N	Jurisdiction	\N
1006700	Ungheni	Ungheni	1002452	\N	Jurisdiction	\N
1006947	Benue	Benue	1002468	\N	Jurisdiction	\N
1007622	Van	Van	1002535	\N	Jurisdiction	\N
1008077	Transportation infrastructure	Transportation infrastructure	1008049	\N	Sector	\N
1008113	Semiconductors & Semiconductor Equipment	Semiconductors & Semiconductor Equipment	1008050	\N	Sector	\N
1008110	Communications equipment	Communications equipment	1008052	\N	Sector	\N
1008112	Electronic equipment, instruments and components	Electronic equipment, instruments and components	1008052	\N	Sector	\N
1008111	Technology hardware, storage and peripherals	Technology hardware, storage and peripherals	1008052	\N	Sector	\N
1008059	Chemicals	Chemicals	1008053	\N	Sector	\N
1008060	Construction Materials	Construction Materials	1008053	\N	Sector	\N
1008061	Containers and packing	Containers and packing	1008053	\N	Sector	\N
1008062	Metals and mining	Metals and mining	1008053	\N	Sector	\N
1008063	Paper and forest products	Paper and forest products	1008053	\N	Sector	\N
1008124	Equity Real Estate Investment Trusts (REITs) 	Equity Real Estate Investment Trusts (REITs) 	1008054	\N	Sector	\N
1008082	Textiles, appral and luxury goods	Textiles, appral and luxury goods	1008035	\N	Sector	\N
1008084	Diversified consumer services	Diversified consumer services	1008036	\N	Sector	\N
1008083	Hotel, restaurants and leisure	Hotel, restaurants and leisure	1008036	\N	Sector	\N
1008085	Distributors	Distributors	1008037	\N	Sector	\N
1008086	Intel and direct marketing retail	Intel and direct marketing retail	1008037	\N	Sector	\N
1008087	Multiline retail	Multiline retail	1008037	\N	Sector	\N
1008088	Speciality retail	Speciality retail	1008037	\N	Sector	\N
1008089	Food and staples retailing	Food and staples retailing	1008038	\N	Sector	\N
1008090	Beverages	Beverages	1008039	\N	Sector	\N
1008091	Food products	Food products	1008039	\N	Sector	\N
1008092	Tobacco	Tobacco	1008039	\N	Sector	\N
1008093	Household products	Household products	1008040	\N	Sector	\N
1008094	Personal products	Personal products	1008040	\N	Sector	\N
1008057	Energy Equipment & Services	Energy Equipment & Services	1008041	\N	Sector	\N
1008058	Oil, Gas & Consumable Fuels	Oil, Gas & Consumable Fuels	1008041	\N	Sector	\N
1008101	Banks	Banks	1008042	\N	Sector	\N
1008102	Thrifts and mortgage finance	Thrifts and mortgage finance	1008042	\N	Sector	\N
1008105	Capital markets	Capital markets	1008043	\N	Sector	\N
1008104	Consumer finance	Consumer finance	1008043	\N	Sector	\N
1008103	Diversified financial services	Diversified financial services	1008043	\N	Sector	\N
1008106	Mortgage Real Estate Investment Trusts (REITs) 	Mortgage Real Estate Investment Trusts (REITs) 	1008043	\N	Sector	\N
1008107	Insurance	Insurance	1008044	\N	Sector	\N
1008095	Health care equipment and supplies	Health care equipment and supplies	1008045	\N	Sector	\N
1008096	Health care providers and services	Health care providers and services	1008045	\N	Sector	\N
1008097	Heath care technology	Heath care technology	1008045	\N	Sector	\N
1008098	Biotechnology	Biotechnology	1008046	\N	Sector	\N
1000018	Administrative	Administrative	\N	\N	PracticeGroup	\N
1000019	Banking	Banking	\N	\N	PracticeGroup	\N
1000020	Commercial	Commercial	\N	\N	PracticeGroup	\N
1000021	Communication	Communication	\N	\N	PracticeGroup	\N
1000022	Constitutional	Constitutional	\N	\N	PracticeGroup	\N
1000023	Corporate	Corporate	\N	\N	PracticeGroup	\N
1000024	Criminal	Criminal	\N	\N	PracticeGroup	\N
1000025	Dispute	Dispute	\N	\N	PracticeGroup	\N
1000026	Employment	Employment	\N	\N	PracticeGroup	\N
1000027	Energy	Energy	\N	\N	PracticeGroup	\N
1000028	Entertainment	Entertainment	\N	\N	PracticeGroup	\N
1000029	Environmental	Environmental	\N	\N	PracticeGroup	\N
1000030	Estate and Succession	Estate and Succession	\N	\N	PracticeGroup	\N
1000031	Family	Family	\N	\N	PracticeGroup	\N
1000032	Finance	Finance	\N	\N	PracticeGroup	\N
1000033	Food and drugs	Food and drugs	\N	\N	PracticeGroup	\N
1000034	Gaming	Gaming	\N	\N	PracticeGroup	\N
1000035	Health care	Health care	\N	\N	PracticeGroup	\N
1000036	Information Security	Information Security	\N	\N	PracticeGroup	\N
1000037	Insurance	Insurance	\N	\N	PracticeGroup	\N
1000038	Intellectual property	Intellectual property	\N	\N	PracticeGroup	\N
1000039	International	International	\N	\N	PracticeGroup	\N
1000040	Personal Injury	Personal Injury	\N	\N	PracticeGroup	\N
1000041	Product Liability	Product Liability	\N	\N	PracticeGroup	\N
1000042	Professional Malpractice	Professional Malpractice	\N	\N	PracticeGroup	\N
1000044	Regulatory	Regulatory	\N	\N	PracticeGroup	\N
1000045	Restructuring	Restructuring	\N	\N	PracticeGroup	\N
1000046	Securities	Securities	\N	\N	PracticeGroup	\N
1000047	Sports	Sports	\N	\N	PracticeGroup	\N
1000048	Tax	Tax	\N	\N	PracticeGroup	\N
1000049	Tort	Tort	\N	\N	PracticeGroup	\N
1000050	Transportation	Transportation	\N	\N	PracticeGroup	\N
1000051	Civil rights	Civil rights	1000018	\N	PracticeGroup	\N
1000052	Elections	Elections	1000018	\N	PracticeGroup	\N
1000053	Government contracts	Government contracts	1000018	\N	PracticeGroup	\N
1000054	Indigenous affairs	Indigenous affairs	1000018	\N	PracticeGroup	\N
1000055	Military	Military	1000018	\N	PracticeGroup	\N
1000057	Public policy and government affairs	Public policy and government affairs	1000018	\N	PracticeGroup	\N
1000058	Utilities	Utilities	1000018	\N	PracticeGroup	\N
1000059	AML	AML	1000019	\N	PracticeGroup	\N
1000061	Antitrust and competition	Antitrust and competition	1000020	\N	PracticeGroup	\N
1000062	Cross-border trade	Cross-border trade	1000020	\N	PracticeGroup	\N
1000063	General transactions	General transactions	1000020	\N	PracticeGroup	\N
1000064	Sales and Procurement	Sales and Procurement	1000020	\N	PracticeGroup	\N
1000066	Media	Media	1000021	\N	PracticeGroup	\N
1000067	Telecommunications	Telecommunications	1000021	\N	PracticeGroup	\N
1000068	Business organisations	Business organisations	1000023	\N	PracticeGroup	\N
1000069	Corporate governance	Corporate governance	1000023	\N	PracticeGroup	\N
1000070	Equity capital markets	Equity capital markets	1000023	\N	PracticeGroup	\N
1000072	Private equity	Private equity	1000023	\N	PracticeGroup	\N
1000073	Venture capital	Venture capital	1000023	\N	PracticeGroup	\N
1000074	Anti-corruption	Anti-corruption	1000024	\N	PracticeGroup	\N
1000075	Asset forfeiture	Asset forfeiture	1000024	\N	PracticeGroup	\N
1000077	Cybercrime	Cybercrime	1000024	\N	PracticeGroup	\N
1000078	Organised crime	Organised crime	1000024	\N	PracticeGroup	\N
1000079	Administrative	Administrative	1000025	\N	PracticeGroup	\N
1000080	Appellate	Appellate	1000025	\N	PracticeGroup	\N
1000081	Arbitration	Arbitration	1000025	\N	PracticeGroup	\N
1000082	Civil proceedings	Civil proceedings	1000025	\N	PracticeGroup	\N
1006035	Navarre	Navarre	1002518	\N	Jurisdiction	\N
1007805	West Virginia	West Virginia	1002544	\N	Jurisdiction	\N
1007809	New Mexico	New Mexico	1002544	\N	Jurisdiction	\N
1007814	Montana	Montana	1002544	\N	Jurisdiction	\N
1007817	Wyoming	Wyoming	1002544	\N	Jurisdiction	\N
1007820	Flores	Flores	1002545	\N	Jurisdiction	\N
1007828	Rivera	Rivera	1002545	\N	Jurisdiction	\N
1007831	Lavalleja	Lavalleja	1002545	\N	Jurisdiction	\N
1007835	Durazno	Durazno	1002545	\N	Jurisdiction	\N
1007841	Surxondaryo	Surxondaryo	1002546	\N	Jurisdiction	\N
1007845	Fergana	Fergana	1002546	\N	Jurisdiction	\N
1007848	Namangan	Namangan	1002546	\N	Jurisdiction	\N
1007852	Saint George	Saint George	1002499	\N	Jurisdiction	\N
1007860	Trujillo	Trujillo	1002549	\N	Jurisdiction	\N
1007863	Delta Amacuro	Delta Amacuro	1002549	\N	Jurisdiction	\N
1007868	Lara	Lara	1002549	\N	Jurisdiction	\N
1007872	Vargas	Vargas	1002549	\N	Jurisdiction	\N
1007877	Saint Thomas Island	Saint Thomas Island	1002539	\N	Jurisdiction	\N
1007883	V??nh Ph??c	Vinh Phuc	1002550	\N	Jurisdiction	\N
1007886	Qu???ng Ninh	Quang Ninh	1002550	\N	Jurisdiction	\N
1007894	Th??i B??nh	Thai Binh	1002550	\N	Jurisdiction	\N
1006395	Friuli Venezia Giulia	Friuli Venezia Giulia	1002416	\N	Jurisdiction	\N
1006400	Basilicate	Basilicate	1002416	\N	Jurisdiction	\N
1006404	Westmoreland	Westmoreland	1002418	\N	Jurisdiction	\N
1006413	Irbid	Irbid	1002421	\N	Jurisdiction	\N
1006416	Zarqa	Zarqa	1002421	\N	Jurisdiction	\N
1006419	Ajlun	Ajlun	1002421	\N	Jurisdiction	\N
1006422	Wakayama	Wakayama	1002419	\N	Jurisdiction	\N
1006430	Gunma	Gunma	1002419	\N	Jurisdiction	\N
1006434	Shiga Prefecture	Shiga Prefecture	1002419	\N	Jurisdiction	\N
1006438	Shimane	Shimane	1002419	\N	Jurisdiction	\N
1006445	Saga Prefecture	Saga Prefecture	1002419	\N	Jurisdiction	\N
1006449	Okayama	Okayama	1002419	\N	Jurisdiction	\N
1006453	Miyazaki	Miyazaki	1002419	\N	Jurisdiction	\N
1006456	Nagasaki	Nagasaki	1002419	\N	Jurisdiction	\N
1006464	Fukushima	Fukushima	1002419	\N	Jurisdiction	\N
1006468	Aomori	Aomori	1002419	\N	Jurisdiction	\N
1006471	Taita Taveta	Taita Taveta	1002423	\N	Jurisdiction	\N
1006479	Marsabit	Marsabit	1002423	\N	Jurisdiction	\N
1006483	Vihiga	Vihiga	1002423	\N	Jurisdiction	\N
1006484	Samburu	Samburu	1002423	\N	Jurisdiction	\N
1006487	Makueni	Makueni	1002423	\N	Jurisdiction	\N
1006494	Kisii	Kisii	1002423	\N	Jurisdiction	\N
1007913	Ti???n Giang	Tien Giang	1002550	\N	Jurisdiction	\N
1007917	H??ng Y??n	Hung Yen	1002550	\N	Jurisdiction	\N
1007924	B??nh Ph?????c	Binh Phuoc	1002550	\N	Jurisdiction	\N
1007929	L??m ?????ng	Lam Dong	1002550	\N	Jurisdiction	\N
1007933	?????c L???k	Dac Lak	1002550	\N	Jurisdiction	\N
1007937	B???c Li??u	Bac Lieu	1002550	\N	Jurisdiction	\N
1007946	Prizren	Prizren	1002425	\N	Jurisdiction	\N
1007949	Gjakova	Gjakova	1002425	\N	Jurisdiction	\N
1007951	Mu?????faz??at al ???udaydah	Muhafaz??at al Hudaydah	1002553	\N	Jurisdiction	\N
1007958	???ajjah	Hajjah	1002553	\N	Jurisdiction	\N
1007961	Omran	Omran	1002553	\N	Jurisdiction	\N
1007969	Gauteng	Gauteng	1002514	\N	Jurisdiction	\N
1007972	Orange Free State	Orange Free State	1002514	\N	Jurisdiction	\N
1006519	Takeo	Takeo	1002347	\N	Jurisdiction	\N
1006526	??t??r M??anchey	Otar Meanchey	1002347	\N	Jurisdiction	\N
1006538	Battambang	Battambang	1002347	\N	Jurisdiction	\N
1002344	Bulgaria	Bulgaria	\N	\N	Jurisdiction	\N
1002346	Burundi	Burundi	\N	\N	Jurisdiction	\N
1002347	Cambodia	Cambodia	\N	\N	Jurisdiction	\N
1002349	Canada	Canada	\N	\N	Jurisdiction	\N
1002351	Cayman Islands	Cayman Islands	\N	\N	Jurisdiction	\N
1002360	Cook Islands	Cook Islands	\N	\N	Jurisdiction	\N
1002363	Cuba	Cuba	\N	\N	Jurisdiction	\N
1002364	Curacao	Curacao	\N	\N	Jurisdiction	\N
1002365	Cyprus	Cyprus	\N	\N	Jurisdiction	\N
1002369	Djibouti	Djibouti	\N	\N	Jurisdiction	\N
1002370	Dominica	Dominica	\N	\N	Jurisdiction	\N
1002371	Dominican Republic	Dominican Republic	\N	\N	Jurisdiction	\N
1002372	East Timor	East Timor	\N	\N	Jurisdiction	\N
1002374	Egypt	Egypt	\N	\N	Jurisdiction	\N
1002376	Equatorial Guinea	Equatorial Guinea	\N	\N	Jurisdiction	\N
1002377	Eritrea	Eritrea	\N	\N	Jurisdiction	\N
1002380	Falkland Islands	Falkland Islands	\N	\N	Jurisdiction	\N
1002381	Faroe Islands	Faroe Islands	\N	\N	Jurisdiction	\N
1002382	Fiji	Fiji	\N	\N	Jurisdiction	\N
1002385	French Guiana	French Guiana	\N	\N	Jurisdiction	\N
1002388	Gabon	Gabon	\N	\N	Jurisdiction	\N
1002389	Gambia	Gambia	\N	\N	Jurisdiction	\N
1002391	Germany	Germany	\N	\N	Jurisdiction	\N
1002392	Ghana	Ghana	\N	\N	Jurisdiction	\N
1002393	Gibraltar	Gibraltar	\N	\N	Jurisdiction	\N
1002395	Greenland	Greenland	\N	\N	Jurisdiction	\N
1002396	Grenada	Grenada	\N	\N	Jurisdiction	\N
1002399	Guatemala	Guatemala	\N	\N	Jurisdiction	\N
1002400	Guernsey	Guernsey	\N	\N	Jurisdiction	\N
1002403	Guyana	Guyana	\N	\N	Jurisdiction	\N
1002404	Haiti	Haiti	\N	\N	Jurisdiction	\N
1002406	Hong Kong	Hong Kong	\N	\N	Jurisdiction	\N
1002407	Hungary	Hungary	\N	\N	Jurisdiction	\N
1002409	India	India	\N	\N	Jurisdiction	\N
1002411	Iran	Iran	\N	\N	Jurisdiction	\N
1002413	Ireland	Ireland	\N	\N	Jurisdiction	\N
1002415	Israel	Israel	\N	\N	Jurisdiction	\N
1002454	Mongolia	Mongolia	\N	\N	Jurisdiction	\N
1002455	Montenegro	Montenegro	\N	\N	Jurisdiction	\N
1002457	Morocco	Morocco	\N	\N	Jurisdiction	\N
1002459	Myanmar	Myanmar	\N	\N	Jurisdiction	\N
1007669	Kocaeli	Kocaeli	1002535	\N	Jurisdiction	\N
1002312	Afghanistan	Afghanistan	\N	\N	Jurisdiction	\N
1002318	Angola	Angola	\N	\N	Jurisdiction	\N
1002320	Antigua and Barbuda	Antigua and Barbuda	\N	\N	Jurisdiction	\N
1002326	Azerbaijan	Azerbaijan	\N	\N	Jurisdiction	\N
1002333	Belize	Belize	\N	\N	Jurisdiction	\N
1002337	Bolivia	Bolivia	\N	\N	Jurisdiction	\N
1002345	Burkina Faso	Burkina Faso	\N	\N	Jurisdiction	\N
1002350	Cape Verde	Cape Verde	\N	\N	Jurisdiction	\N
1002352	Central African Republic	Central African Republic	\N	\N	Jurisdiction	\N
1002358	Colombia	Colombia	\N	\N	Jurisdiction	\N
1002361	Costa Rica	Costa Rica	\N	\N	Jurisdiction	\N
1002366	Czech Republic	Czech Republic	\N	\N	Jurisdiction	\N
1002375	El Salvador	El Salvador	\N	\N	Jurisdiction	\N
1002379	Ethiopia	Ethiopia	\N	\N	Jurisdiction	\N
1002383	Finland	Finland	\N	\N	Jurisdiction	\N
1002386	French Polynesia	French Polynesia	\N	\N	Jurisdiction	\N
1002390	Georgia	Georgia	\N	\N	Jurisdiction	\N
1002394	Greece	Greece	\N	\N	Jurisdiction	\N
1002397	Guadeloupe	Guadeloupe	\N	\N	Jurisdiction	\N
1002405	Honduras	Honduras	\N	\N	Jurisdiction	\N
1002408	Iceland	Iceland	\N	\N	Jurisdiction	\N
1002412	Iraq	Iraq	\N	\N	Jurisdiction	\N
1002418	Jamaica	Jamaica	\N	\N	Jurisdiction	\N
1002421	Jordan	Jordan	\N	\N	Jurisdiction	\N
1002425	Kosovo	Kosovo	\N	\N	Jurisdiction	\N
1002432	Liberia	Liberia	\N	\N	Jurisdiction	\N
1002461	Nauru	Nauru	\N	\N	Jurisdiction	\N
1002462	Nepal	Nepal	\N	\N	Jurisdiction	\N
1002465	New Zealand	New Zealand	\N	\N	Jurisdiction	\N
1002466	Nicaragua	Nicaragua	\N	\N	Jurisdiction	\N
1002467	Niger	Niger	\N	\N	Jurisdiction	\N
1002469	Niue	Niue	\N	\N	Jurisdiction	\N
1002471	North Korea	North Korea	\N	\N	Jurisdiction	\N
1002522	Svalbard and Jan Mayen	Svalbard and Jan Mayen	\N	\N	Jurisdiction	\N
1002523	Swaziland	Swaziland	\N	\N	Jurisdiction	\N
1002526	Syria	Syria	\N	\N	Jurisdiction	\N
1002527	Taiwan	Taiwan	\N	\N	Jurisdiction	\N
1002528	Tajikistan	Tajikistan	\N	\N	Jurisdiction	\N
1002456	Montserrat	Montserrat	\N	\N	Jurisdiction	\N
1002460	Namibia	Namibia	\N	\N	Jurisdiction	\N
1002463	Netherlands	Netherlands	\N	\N	Jurisdiction	\N
1002472	Northern Mariana Islands	Northern Mariana Islands	\N	\N	Jurisdiction	\N
1002477	Palestinian Territory	Palestinian Territory	\N	\N	Jurisdiction	\N
1002482	Philippines	Philippines	\N	\N	Jurisdiction	\N
1002490	Romania	Romania	\N	\N	Jurisdiction	\N
1002493	Saint Barthelemy	Saint Barthelemy	\N	\N	Jurisdiction	\N
1002499	Saint Vincent and the Grenadines	Saint Vincent and the Grenadines	\N	\N	Jurisdiction	\N
1002416	Italy	Italy	\N	\N	Jurisdiction	\N
1002417	Ivory Coast	Ivory Coast	\N	\N	Jurisdiction	\N
1002420	Jersey	Jersey	\N	\N	Jurisdiction	\N
1002422	Kazakhstan	Kazakhstan	\N	\N	Jurisdiction	\N
1002423	Kenya	Kenya	\N	\N	Jurisdiction	\N
1002426	Kuwait	Kuwait	\N	\N	Jurisdiction	\N
1002427	Kyrgyzstan	Kyrgyzstan	\N	\N	Jurisdiction	\N
1002428	Laos	Laos	\N	\N	Jurisdiction	\N
1002431	Lesotho	Lesotho	\N	\N	Jurisdiction	\N
1002433	Libya	Libya	\N	\N	Jurisdiction	\N
1002434	Liechtenstein	Liechtenstein	\N	\N	Jurisdiction	\N
1002437	Macao	Macao	\N	\N	Jurisdiction	\N
1002439	Madagascar	Madagascar	\N	\N	Jurisdiction	\N
1002440	Malawi	Malawi	\N	\N	Jurisdiction	\N
1002443	Mali	Mali	\N	\N	Jurisdiction	\N
1002444	Malta	Malta	\N	\N	Jurisdiction	\N
1002446	Martinique	Martinique	\N	\N	Jurisdiction	\N
1002447	Mauritania	Mauritania	\N	\N	Jurisdiction	\N
1002450	Mexico	Mexico	\N	\N	Jurisdiction	\N
1002451	Micronesia	Micronesia	\N	\N	Jurisdiction	\N
1002537	Turks and Caicos Islands	Turks and Caicos Islands	\N	\N	Jurisdiction	\N
1002542	United Arab Emirates	United Arab Emirates	\N	\N	Jurisdiction	\N
1002546	Uzbekistan	Uzbekistan	\N	\N	Jurisdiction	\N
1002550	Vietnam	Vietnam	\N	\N	Jurisdiction	\N
1005415	Santa Fe	Santa Fe	1002321	\N	Jurisdiction	\N
1005421	Formosa	Formosa	1002321	\N	Jurisdiction	\N
1005424	Rio Negro	Rio Negro	1002321	\N	Jurisdiction	\N
1005427	Tierra del Fuego	Tierra del Fuego	1002321	\N	Jurisdiction	\N
1005433	Mendoza	Mendoza	1002321	\N	Jurisdiction	\N
1005440	Lower Austria	Lower Austria	1002325	\N	Jurisdiction	\N
1005444	Vorarlberg	Vorarlberg	1002325	\N	Jurisdiction	\N
1005447	South Australia	South Australia	1002324	\N	Jurisdiction	\N
1005454	Australian Capital Territory	Australian Capital Territory	1002324	\N	Jurisdiction	\N
1005462	L??nk??ran	L??nk??ran	1002326	\N	Jurisdiction	\N
1007851	Andijon	Andijon	1002546	\N	Jurisdiction	\N
1007699	Point Fortin	Point Fortin	1002533	\N	Jurisdiction	\N
1007704	Taiwan	Taiwan	1002527	\N	Jurisdiction	\N
1007712	Geita	Geita	1002529	\N	Jurisdiction	\N
1007719	Mara	Mara	1002529	\N	Jurisdiction	\N
1007723	Zanzibar Central/South	Zanzibar Central/South	1002529	\N	Jurisdiction	\N
1007728	Morogoro	Morogoro	1002529	\N	Jurisdiction	\N
1007731	Ruvuma	Ruvuma	1002529	\N	Jurisdiction	\N
1007739	Zaporizhia	Zaporizhia	1002541	\N	Jurisdiction	\N
1007742	Kirovohrad	Kirovohrad	1002541	\N	Jurisdiction	\N
1007750	Kiev	Kiev	1002541	\N	Jurisdiction	\N
1007754	Kherson	Kherson	1002541	\N	Jurisdiction	\N
1007757	Khmelnytskyi	Khmelnytskyi	1002541	\N	Jurisdiction	\N
1007761	Ivano-Frankivsk	Ivano-Frankivsk	1002541	\N	Jurisdiction	\N
1007770	Kentucky	Kentucky	1002544	\N	Jurisdiction	\N
1007772	Washington, D.C.	Washington, D.C.	1002544	\N	Jurisdiction	\N
1007778	Kansas	Kansas	1002544	\N	Jurisdiction	\N
1007781	Missouri	Missouri	1002544	\N	Jurisdiction	\N
1007785	Ohio	Ohio	1002544	\N	Jurisdiction	\N
1007793	Massachusetts	Massachusetts	1002544	\N	Jurisdiction	\N
1007797	North Dakota	North Dakota	1002544	\N	Jurisdiction	\N
1005561	Ruyigi	Ruyigi	1002346	\N	Jurisdiction	\N
1005564	Muyinga	Muyinga	1002346	\N	Jurisdiction	\N
1005571	Atlantique	Atlantique	1002334	\N	Jurisdiction	\N
1005575	Donga	Donga	1002334	\N	Jurisdiction	\N
1005578	Hamilton city	Hamilton city	1002335	\N	Jurisdiction	\N
1005586	Chuquisaca	Chuquisaca	1002337	\N	Jurisdiction	\N
1005591	Bonaire	Bonaire	1002338	\N	Jurisdiction	\N
1005594	Par??	Para	1002341	\N	Jurisdiction	\N
1005597	Alagoas	Alagoas	1002341	\N	Jurisdiction	\N
1005601	Bahia	Bahia	1002341	\N	Jurisdiction	\N
1005608	Minas Gerais	Minas Gerais	1002341	\N	Jurisdiction	\N
1005613	Mato Grosso do Sul	Mato Grosso do Sul	1002341	\N	Jurisdiction	\N
1005621	Thimphu	Thimphu	1002336	\N	Jurisdiction	\N
1005624	Chirang	Chirang	1002336	\N	Jurisdiction	\N
1005631	North East	North East	1002340	\N	Jurisdiction	\N
1005635	Grodnenskaya	Grodnenskaya	1002331	\N	Jurisdiction	\N
1005640	Orange Walk	Orange Walk	1002333	\N	Jurisdiction	\N
1005647	Prince Edward Island	Prince Edward Island	1002349	\N	Jurisdiction	\N
1005653	Northwest Territories	Northwest Territories	1002349	\N	Jurisdiction	\N
1005658	Kasa??-Oriental	Kasai-Oriental	1002367	\N	Jurisdiction	\N
1005662	Bas-Congo	Bas-Congo	1002367	\N	Jurisdiction	\N
1005666	Ouaka	Ouaka	1002352	\N	Jurisdiction	\N
1005673	Nana-Gr??bizi	Nana-Grebizi	1002352	\N	Jurisdiction	\N
1005676	Nana-Mamb??r??	Nana-Mambere	1002352	\N	Jurisdiction	\N
1005685	Likouala	Likouala	1002488	\N	Jurisdiction	\N
1005690	Vaud	Vaud	1002525	\N	Jurisdiction	\N
1005691	Saint Gallen	Saint Gallen	1002525	\N	Jurisdiction	\N
1005695	Valais	Valais	1002525	\N	Jurisdiction	\N
1005706	Basel-City	Basel-City	1002525	\N	Jurisdiction	\N
1005709	Haut-Sassandra	Haut-Sassandra	1002417	\N	Jurisdiction	\N
1005714	Bas-Sassandra	Bas-Sassandra	1002417	\N	Jurisdiction	\N
1005721	Sud-Como??	Sud-Comoe	1002417	\N	Jurisdiction	\N
1005725	Valpara??so	Valparaiso	1002354	\N	Jurisdiction	\N
1005729	Biob??o	Biobio	1002354	\N	Jurisdiction	\N
1005737	Coquimbo	Coquimbo	1002354	\N	Jurisdiction	\N
1005741	Far North	Far North	1002348	\N	Jurisdiction	\N
1005744	South-West Province	South-West Province	1002348	\N	Jurisdiction	\N
1005750	Tibet Autonomous Region	Tibet Autonomous Region	1002355	\N	Jurisdiction	\N
1005754	Shandong Sheng	Shandong Sheng	1002355	\N	Jurisdiction	\N
1005763	Hubei	Hubei	1002355	\N	Jurisdiction	\N
1005767	Shaanxi	Shaanxi	1002355	\N	Jurisdiction	\N
1005769	Guangxi Zhuangzu Zizhiqu	Guangxi Zhuangzu Zizhiqu	1002355	\N	Jurisdiction	\N
1005776	Qinghai Sheng	Qinghai Sheng	1002355	\N	Jurisdiction	\N
1005779	Jilin Sheng	Jilin Sheng	1002355	\N	Jurisdiction	\N
1005787	Norte de Santander	Norte de Santander	1002358	\N	Jurisdiction	\N
1005792	Boyac??	Boyaca	1002358	\N	Jurisdiction	\N
1005795	Arauca	Arauca	1002358	\N	Jurisdiction	\N
1005811	Cartago	Cartago	1002361	\N	Jurisdiction	\N
1005814	Alajuela	Alajuela	1002361	\N	Jurisdiction	\N
1005818	Granma	Granma	1002363	\N	Jurisdiction	\N
1005821	Camag??ey	Camaguey	1002363	\N	Jurisdiction	\N
1005823	Matanzas	Matanzas	1002363	\N	Jurisdiction	\N
1005825	Villa Clara	Villa Clara	1002363	\N	Jurisdiction	\N
1005829	Artemisa	Artemisa	1002363	\N	Jurisdiction	\N
1005833	Isla de la Juventud	Isla de la Juventud	1002363	\N	Jurisdiction	\N
1005837	Santa Catarina do Fogo	Santa Catarina do Fogo	1002350	\N	Jurisdiction	\N
1005843	Keryneia	Keryneia	1002365	\N	Jurisdiction	\N
1005847	Vyso??ina	Vysocina	1002366	\N	Jurisdiction	\N
1005854	Central Bohemia	Central Bohemia	1002366	\N	Jurisdiction	\N
1005859	Rheinland-Pfalz	Rheinland-Pfalz	1002391	\N	Jurisdiction	\N
1005863	Saxony-Anhalt	Saxony-Anhalt	1002391	\N	Jurisdiction	\N
1005867	Mecklenburg-Vorpommern	Mecklenburg-Vorpommern	1002391	\N	Jurisdiction	\N
1005871	Schleswig-Holstein	Schleswig-Holstein	1002391	\N	Jurisdiction	\N
1005877	Ali Sabieh	Ali Sabieh	1002369	\N	Jurisdiction	\N
1005885	Santiago	Santiago	1002371	\N	Jurisdiction	\N
1005889	San Pedro de Macor??s	San Pedro de Macoris	1002371	\N	Jurisdiction	\N
1005893	Monte Cristi	Monte Cristi	1002371	\N	Jurisdiction	\N
1005902	Valverde	Valverde	1002371	\N	Jurisdiction	\N
1005906	Dajab??n	Dajabon	1002371	\N	Jurisdiction	\N
1005910	Peravia	Peravia	1002371	\N	Jurisdiction	\N
1005914	Tipaza	Tipaza	1002315	\N	Jurisdiction	\N
1005917	Tlemcen	Tlemcen	1002315	\N	Jurisdiction	\N
1005924	A??n Defla	Ain Defla	1002315	\N	Jurisdiction	\N
1005928	Tamanghasset	Tamanghasset	1002315	\N	Jurisdiction	\N
1005932	Souk Ahras	Souk Ahras	1002315	\N	Jurisdiction	\N
1005940	Alger	Alger	1002315	\N	Jurisdiction	\N
1005942	Bordj Bou Arr??ridj	Bordj Bou Arreridj	1002315	\N	Jurisdiction	\N
1005948	Laghouat	Laghouat	1002315	\N	Jurisdiction	\N
1007899	S??n La	Son La	1002550	\N	Jurisdiction	\N
1007905	Qu???ng Ng??i	Quang Ngai	1002550	\N	Jurisdiction	\N
1007910	Ninh B??nh	Ninh Binh	1002550	\N	Jurisdiction	\N
1006022	Extremadura	Extremadura	1002518	\N	Jurisdiction	\N
1006031	Castille and Le??n	Castille and Leon	1002518	\N	Jurisdiction	\N
1006038	La Rioja	La Rioja	1002518	\N	Jurisdiction	\N
1006054	Ostrobothnia	Ostrobothnia	1002383	\N	Jurisdiction	\N
1006058	Southern Savonia	Southern Savonia	1002383	\N	Jurisdiction	\N
1006063	South Karelia	South Karelia	1002383	\N	Jurisdiction	\N
1006068	North Karelia	North Karelia	1002383	\N	Jurisdiction	\N
1006072	Pohnpei	Pohnpei	1002451	\N	Jurisdiction	\N
1006075	Alsace-Champagne-Ardenne-Lorraine	Alsace-Champagne-Ardenne-Lorraine	1002384	\N	Jurisdiction	\N
1006080	Aquitaine-Limousin-Poitou-Charentes	Aquitaine-Limousin-Poitou-Charentes	1002384	\N	Jurisdiction	\N
1006081	Centre	Centre	1002384	\N	Jurisdiction	\N
1006082	Bourgogne-Franche-Comt??	Bourgogne-Franche-Comte	1002384	\N	Jurisdiction	\N
1006093	Moyen-Ogoou??	Moyen-Ogooue	1002388	\N	Jurisdiction	\N
1006097	Scotland	Scotland	1002543	\N	Jurisdiction	\N
1006100	Samegrelo and Zemo Svaneti	Samegrelo and Zemo Svaneti	1002390	\N	Jurisdiction	\N
1006106	Kvemo Kartli	Kvemo Kartli	1002390	\N	Jurisdiction	\N
1006111	St Peter Port	St Peter Port	1002400	\N	Jurisdiction	\N
1006115	Upper West	Upper West	1002392	\N	Jurisdiction	\N
1006119	Eastern	Eastern	1002392	\N	Jurisdiction	\N
1006122	Sermersooq	Sermersooq	1002395	\N	Jurisdiction	\N
1006126	Labe	Labe	1002401	\N	Jurisdiction	\N
1006134	Guadeloupe	Guadeloupe	1002397	\N	Jurisdiction	\N
1006137	Litoral	Litoral	1002376	\N	Jurisdiction	\N
1006140	Peloponnese	Peloponnese	1002394	\N	Jurisdiction	\N
1006147	Central Macedonia	Central Macedonia	1002394	\N	Jurisdiction	\N
1005634	Vitebsk	Vitebsk	1002331	\N	Jurisdiction	\N
1006157	Escuintla	Escuintla	1002399	\N	Jurisdiction	\N
1006160	Suchitepeque	Suchitepeque	1002399	\N	Jurisdiction	\N
1006164	Baja Verapaz	Baja Verapaz	1002399	\N	Jurisdiction	\N
1006169	Jalapa	Jalapa	1002399	\N	Jurisdiction	\N
1006177	Mangilao	Mangilao	1002398	\N	Jurisdiction	\N
1006180	East Berbice-Corentyne	East Berbice-Corentyne	1002403	\N	Jurisdiction	\N
1006185	Tuen Mun	Tuen Mun	1002406	\N	Jurisdiction	\N
1006193	Atl??ntida	Atlantida	1002405	\N	Jurisdiction	\N
1005420	Chaco	Chaco	1002321	\N	Jurisdiction	\N
1005556	Makamba	Makamba	1002346	\N	Jurisdiction	\N
1006307	Madhya Pradesh	Madhya Pradesh	1002409	\N	Jurisdiction	\N
1006312	Himachal Pradesh	Himachal Pradesh	1002409	\N	Jurisdiction	\N
1006317	West Bengal	West Bengal	1002409	\N	Jurisdiction	\N
1006321	Jharkhand	Jharkhand	1002409	\N	Jurisdiction	\N
1006329	Daman and Diu	Daman and Diu	1002409	\N	Jurisdiction	\N
1006333	Salah ad Din Governorate	Salah ad Din Governorate	1002412	\N	Jurisdiction	\N
1006339	At Ta??m??m	At Ta??mim	1002412	\N	Jurisdiction	\N
1006342	Mayorality of Baghdad	Mayorality of Baghdad	1002412	\N	Jurisdiction	\N
1006343	W??si??	Wasit	1002412	\N	Jurisdiction	\N
1006344	Al Muthann??	Al Muthanna	1002412	\N	Jurisdiction	\N
1007229	Br??ila	Braila	1002490	\N	Jurisdiction	\N
1006351	Lorest??n	Lorestan	1002411	\N	Jurisdiction	\N
1006361	G??l??n	Gilan	1002411	\N	Jurisdiction	\N
1006363	??z????rb??yj??n-e Gharb??	Az??arbayjan-e Gharbi	1002411	\N	Jurisdiction	\N
1006368	Chah??r Ma?????ll va Bakht????r??	Chahar Mahall va Bakhtiari	1002411	\N	Jurisdiction	\N
1006374	Khor??s??n-e Jon??b??	Khorasan-e Jonubi	1002411	\N	Jurisdiction	\N
1007211	Satu Mare	Satu Mare	1002490	\N	Jurisdiction	\N
1006379	Sistan and Baluchestan	Sistan and Baluchestan	1002411	\N	Jurisdiction	\N
1006385	Apulia	Apulia	1002416	\N	Jurisdiction	\N
1006389	Latium	Latium	1002416	\N	Jurisdiction	\N
1006392	Piedmont	Piedmont	1002416	\N	Jurisdiction	\N
1006501	Isiolo	Isiolo	1002423	\N	Jurisdiction	\N
1006504	Embu	Embu	1002423	\N	Jurisdiction	\N
1006507	Nyandarua	Nyandarua	1002423	\N	Jurisdiction	\N
1006515	Bishkek	Bishkek	1002427	\N	Jurisdiction	\N
1007975	KwaZulu-Natal	KwaZulu-Natal	1002514	\N	Jurisdiction	\N
1007976	Eastern Cape	Eastern Cape	1002514	\N	Jurisdiction	\N
1007978	Luapula	Luapula	1002554	\N	Jurisdiction	\N
1007979	Northern	Northern	1002554	\N	Jurisdiction	\N
1007980	Southern	Southern	1002554	\N	Jurisdiction	\N
1007981	Western	Western	1002554	\N	Jurisdiction	\N
1007982	Eastern	Eastern	1002554	\N	Jurisdiction	\N
1007984	Central	Central	1002554	\N	Jurisdiction	\N
1007985	Lusaka	Lusaka	1002554	\N	Jurisdiction	\N
1007986	North-Western	North-Western	1002554	\N	Jurisdiction	\N
1007988	Matabeleland North	Matabeleland North	1002555	\N	Jurisdiction	\N
1006542	Saint George Basseterre	Saint George Basseterre	1002495	\N	Jurisdiction	\N
1006547	P'y??ngan-namdo	P'yongan-namdo	1002471	\N	Jurisdiction	\N
1006556	Jeollanam-do	Jeollanam-do	1002516	\N	Jurisdiction	\N
1006559	Chungcheongnam-do	Chungcheongnam-do	1002516	\N	Jurisdiction	\N
1006568	Incheon	Incheon	1002516	\N	Jurisdiction	\N
1006571	Mu?????faz??at ???awall??	Muhafaz??at Hawalli	1002426	\N	Jurisdiction	\N
1006580	Batys Qazaqstan	Batys Qazaqstan	1002422	\N	Jurisdiction	\N
1006585	Zhambyl	Zhambyl	1002422	\N	Jurisdiction	\N
1006588	Solt??stik Qazaqstan	Soltustik Qazaqstan	1002422	\N	Jurisdiction	\N
1006593	Almaty Qalasy	Almaty Qalasy	1002422	\N	Jurisdiction	\N
1006598	Oud??mxai	Oudomxai	1002428	\N	Jurisdiction	\N
1006606	Liban-Nord	Liban-Nord	1002430	\N	Jurisdiction	\N
1006610	Nabat??y??	Nabatiye	1002430	\N	Jurisdiction	\N
1006614	Western	Western	1002519	\N	Jurisdiction	\N
1006617	Eastern Province	Eastern Province	1002519	\N	Jurisdiction	\N
1006620	Central	Central	1002519	\N	Jurisdiction	\N
1006628	Maryland	Maryland	1002432	\N	Jurisdiction	\N
1006631	Grand Bassa	Grand Bassa	1002432	\N	Jurisdiction	\N
1006634	Mohale??s Hoek	Mohale??s Hoek	1002431	\N	Jurisdiction	\N
1006643	Klaip??dos apskritis	Klaipedos apskritis	1002435	\N	Jurisdiction	\N
1006648	Alytaus apskritis	Alytaus apskritis	1002435	\N	Jurisdiction	\N
1006653	Tukuma Rajons	Tukuma Rajons	1002429	\N	Jurisdiction	\N
1006658	J??rmala	Jurmala	1002429	\N	Jurisdiction	\N
1006666	Sha???b??yat al W???????t	Sha'biyat al Wahat	1002433	\N	Jurisdiction	\N
1006670	An Nuq???? al Khams	An Nuqat al Khams	1002433	\N	Jurisdiction	\N
1006676	Surt	Surt	1002433	\N	Jurisdiction	\N
1006679	Sha???b??yat N??l??t	Sha'biyat Nalut	1002433	\N	Jurisdiction	\N
1006688	Rabat-Sal??-Zemmour-Za??r	Rabat-Sale-Zemmour-Zaer	1002457	\N	Jurisdiction	\N
1006694	Grand Casablanca	Grand Casablanca	1002457	\N	Jurisdiction	\N
1006698	Oued ed Dahab-Lagouira	Oued ed Dahab-Lagouira	1002457	\N	Jurisdiction	\N
1006704	Raionul Soroca	Raionul Soroca	1002452	\N	Jurisdiction	\N
1006708	Flore??ti	Floresti	1002452	\N	Jurisdiction	\N
1006712	Chi??in??u	Chisinau	1002452	\N	Jurisdiction	\N
1006716	Podgorica	Podgorica	1002455	\N	Jurisdiction	\N
1006724	Atsinanana	Atsinanana	1002439	\N	Jurisdiction	\N
1006727	Bongolava	Bongolava	1002439	\N	Jurisdiction	\N
1006730	Atsimo-Andrefana	Atsimo-Andrefana	1002439	\N	Jurisdiction	\N
1006736	Vatovavy Fitovinany	Vatovavy Fitovinany	1002439	\N	Jurisdiction	\N
1006740	Melaky	Melaky	1002439	\N	Jurisdiction	\N
1006743	Amoron'i Mania	Amoron'i Mania	1002439	\N	Jurisdiction	\N
1006745	Diana	Diana	1002439	\N	Jurisdiction	\N
1006748	Vinica	Vinica	1002438	\N	Jurisdiction	\N
1006752	Studeni??ani	Studenicani	1002438	\N	Jurisdiction	\N
1006756	Karpo??	Karpos	1002438	\N	Jurisdiction	\N
1006759	Radovi??	Radovis	1002438	\N	Jurisdiction	\N
1006763	Negotino	Negotino	1002438	\N	Jurisdiction	\N
1006766	Kriva Palanka	Kriva Palanka	1002438	\N	Jurisdiction	\N
1006771	Gostivar	Gostivar	1002438	\N	Jurisdiction	\N
1006775	Brvenica	Brvenica	1002438	\N	Jurisdiction	\N
1006779	??air	Cair	1002438	\N	Jurisdiction	\N
1007188	Balad??yat ad Daw???ah	Baladiyat ad Dawhah	1002487	\N	Jurisdiction	\N
1007189	R??union	Reunion	1002489	\N	Jurisdiction	\N
1007191	Bra??ov	Brasov	1002490	\N	Jurisdiction	\N
1007192	S??laj	Salaj	1002490	\N	Jurisdiction	\N
1007193	Hunedoara	Hunedoara	1002490	\N	Jurisdiction	\N
1007195	Maramure??	Maramures	1002490	\N	Jurisdiction	\N
1007196	Suceava	Suceava	1002490	\N	Jurisdiction	\N
1007197	Vaslui	Vaslui	1002490	\N	Jurisdiction	\N
1007199	Cluj	Cluj	1002490	\N	Jurisdiction	\N
1007200	Tulcea	Tulcea	1002490	\N	Jurisdiction	\N
1007201	Mure??	Mures	1002490	\N	Jurisdiction	\N
1007203	Neam??	Neamt	1002490	\N	Jurisdiction	\N
1007204	Gorj	Gorj	1002490	\N	Jurisdiction	\N
1007206	Timi??	Timis	1002490	\N	Jurisdiction	\N
1007207	Gala??i	Galati	1002490	\N	Jurisdiction	\N
1007208	Olt	Olt	1002490	\N	Jurisdiction	\N
1007210	Alba	Alba	1002490	\N	Jurisdiction	\N
1007213	V??lcea	Valcea	1002490	\N	Jurisdiction	\N
1007214	Buz??u	Buzau	1002490	\N	Jurisdiction	\N
1007216	Prahova	Prahova	1002490	\N	Jurisdiction	\N
1007217	Arge??	Arges	1002490	\N	Jurisdiction	\N
1007218	C??l??ra??i	Calarasi	1002490	\N	Jurisdiction	\N
1007220	Constan??a	Constanta	1002490	\N	Jurisdiction	\N
1007221	Bac??u	Bacau	1002490	\N	Jurisdiction	\N
1007222	Ia??i	Iasi	1002490	\N	Jurisdiction	\N
1007223	Giurgiu	Giurgiu	1002490	\N	Jurisdiction	\N
1007225	Dolj	Dolj	1002490	\N	Jurisdiction	\N
1007226	Mehedin??i	Mehedinti	1002490	\N	Jurisdiction	\N
1007228	Bucure??ti	Bucuresti	1002490	\N	Jurisdiction	\N
1007231	Arad	Arad	1002490	\N	Jurisdiction	\N
1007232	Vojvodina	Vojvodina	1002505	\N	Jurisdiction	\N
1007233	Central Serbia	Central Serbia	1002505	\N	Jurisdiction	\N
1007234	Tverskaya	Tverskaya	1002491	\N	Jurisdiction	\N
1007236	Rjazan	Rjazan	1002491	\N	Jurisdiction	\N
1007237	Moscow	Moscow	1002491	\N	Jurisdiction	\N
1007238	Rostov	Rostov	1002491	\N	Jurisdiction	\N
1007239	MO	MO	1002491	\N	Jurisdiction	\N
1007241	Brjansk	Brjansk	1002491	\N	Jurisdiction	\N
1007242	Volgograd	Volgograd	1002491	\N	Jurisdiction	\N
1007244	Tambov	Tambov	1002491	\N	Jurisdiction	\N
1007245	Stavropol'skiy	Stavropol'skiy	1002491	\N	Jurisdiction	\N
1007246	Kursk	Kursk	1002491	\N	Jurisdiction	\N
1007248	Karachayevo-Cherkesiya	Karachayevo-Cherkesiya	1002491	\N	Jurisdiction	\N
1007250	Penza	Penza	1002491	\N	Jurisdiction	\N
1007400	Kolda	Kolda	1002504	\N	Jurisdiction	\N
1007548	Roi Et	Roi Et	1002530	\N	Jurisdiction	\N
1007853	Nueva Esparta	Nueva Esparta	1002549	\N	Jurisdiction	\N
1007854	Anzo??tegui	Anzoategui	1002549	\N	Jurisdiction	\N
1007855	Barinas	Barinas	1002549	\N	Jurisdiction	\N
1007857	Yaracuy	Yaracuy	1002549	\N	Jurisdiction	\N
1007858	Aragua	Aragua	1002549	\N	Jurisdiction	\N
1007859	Portuguesa	Portuguesa	1002549	\N	Jurisdiction	\N
1007861	Carabobo	Carabobo	1002549	\N	Jurisdiction	\N
1007862	Bol??var	Bolivar	1002549	\N	Jurisdiction	\N
1007864	Cojedes	Cojedes	1002549	\N	Jurisdiction	\N
1006786	Kayes	Kayes	1002443	\N	Jurisdiction	\N
1006793	Mandalay	Mandalay	1002459	\N	Jurisdiction	\N
1006797	Tanintharyi	Tanintharyi	1002459	\N	Jurisdiction	\N
1006801	Kayin	Kayin	1002459	\N	Jurisdiction	\N
1006807	Bayan-??lgiy	Bayan-Olgiy	1002454	\N	Jurisdiction	\N
1006812	H??vsg??l	Hovsgol	1002454	\N	Jurisdiction	\N
1006816	Darhan Uul	Darhan Uul	1002454	\N	Jurisdiction	\N
1006822	Central Aimak	Central Aimak	1002454	\N	Jurisdiction	\N
1006826	Tiris Zemmour	Tiris Zemmour	1002447	\N	Jurisdiction	\N
1006836	Saint Anthony	Saint Anthony	1002456	\N	Jurisdiction	\N
1006839	Il-Belt Valletta	Il-Belt Valletta	1002444	\N	Jurisdiction	\N
1006844	Pamplemousses	Pamplemousses	1002448	\N	Jurisdiction	\N
1006848	Rivi??re du Rempart	Riviere du Rempart	1002448	\N	Jurisdiction	\N
1006853	Central Region	Central Region	1002440	\N	Jurisdiction	\N
1006858	Puebla	Puebla	1002450	\N	Jurisdiction	\N
1006864	Yucat??n	Yucatan	1002450	\N	Jurisdiction	\N
1006868	Tlaxcala	Tlaxcala	1002450	\N	Jurisdiction	\N
1007024	Nelson	Nelson	1002465	\N	Jurisdiction	\N
1007029	Bay of Plenty	Bay of Plenty	1002465	\N	Jurisdiction	\N
1007038	Az?? Z????hirah	Az?? Z??ahirah	1002474	\N	Jurisdiction	\N
1007043	Veraguas	Veraguas	1002478	\N	Jurisdiction	\N
1007047	Bocas del Toro	Bocas del Toro	1002478	\N	Jurisdiction	\N
1007051	San Mart??n	San Martin	1002481	\N	Jurisdiction	\N
1007055	Lambayeque	Lambayeque	1002481	\N	Jurisdiction	\N
1007058	Cajamarca	Cajamarca	1002481	\N	Jurisdiction	\N
1007062	Madre de Dios	Madre de Dios	1002481	\N	Jurisdiction	\N
1007067	Moquegua	Moquegua	1002481	\N	Jurisdiction	\N
1007074	Apur??mac	Apurimac	1002481	\N	Jurisdiction	\N
1007077	National Capital	National Capital	1002479	\N	Jurisdiction	\N
1007083	East New Britain	East New Britain	1002479	\N	Jurisdiction	\N
1007089	Autonomous Region in Muslim Mindanao	Autonomous Region in Muslim Mindanao	1002482	\N	Jurisdiction	\N
1007098	Central Visayas	Central Visayas	1002482	\N	Jurisdiction	\N
1007102	Soccsksargen	Soccsksargen	1002482	\N	Jurisdiction	\N
1007106	Azad Kashmir	Azad Kashmir	1002475	\N	Jurisdiction	\N
1007114	Lesser Poland Voivodeship	Lesser Poland Voivodeship	1002484	\N	Jurisdiction	\N
1007120	Greater Poland Voivodeship	Greater Poland Voivodeship	1002484	\N	Jurisdiction	\N
1007125	West Pomeranian Voivodeship	West Pomeranian Voivodeship	1002484	\N	Jurisdiction	\N
1007132	Caguas	Caguas	1002486	\N	Jurisdiction	\N
1007136	Cayey	Cayey	1002486	\N	Jurisdiction	\N
1007139	Guaynabo	Guaynabo	1002486	\N	Jurisdiction	\N
1007146	Vega Baja	Vega Baja	1002486	\N	Jurisdiction	\N
1007150	Lisbon	Lisbon	1002485	\N	Jurisdiction	\N
1007152	Set??bal	Setubal	1002485	\N	Jurisdiction	\N
1007158	Castelo Branco	Castelo Branco	1002485	\N	Jurisdiction	\N
1007163	Viana do Castelo	Viana do Castelo	1002485	\N	Jurisdiction	\N
1007167	Coimbra	Coimbra	1002485	\N	Jurisdiction	\N
1007174	Misiones	Misiones	1002480	\N	Jurisdiction	\N
1007178	Itap??a	Itapua	1002480	\N	Jurisdiction	\N
1007181	Caazap??	Caazapa	1002480	\N	Jurisdiction	\N
1007190	Teleorman	Teleorman	1002490	\N	Jurisdiction	\N
1007194	Ilfov	Ilfov	1002490	\N	Jurisdiction	\N
1007198	Ialomi??a	Ialomita	1002490	\N	Jurisdiction	\N
1007202	Covasna	Covasna	1002490	\N	Jurisdiction	\N
1007205	D??mbovi??a	Dambovita	1002490	\N	Jurisdiction	\N
1007209	Sibiu	Sibiu	1002490	\N	Jurisdiction	\N
1007224	Vrancea	Vrancea	1002490	\N	Jurisdiction	\N
1007227	Boto??ani	Botosani	1002490	\N	Jurisdiction	\N
1007235	St.-Petersburg	St.-Petersburg	1002491	\N	Jurisdiction	\N
1007240	Chelyabinsk	Chelyabinsk	1002491	\N	Jurisdiction	\N
1007243	Samara	Samara	1002491	\N	Jurisdiction	\N
1007247	Tatarstan	Tatarstan	1002491	\N	Jurisdiction	\N
1007254	Krasnodarskiy	Krasnodarskiy	1002491	\N	Jurisdiction	\N
1007263	Bashkortostan	Bashkortostan	1002491	\N	Jurisdiction	\N
1007267	Udmurtiya	Udmurtiya	1002491	\N	Jurisdiction	\N
1007271	North Ossetia	North Ossetia	1002491	\N	Jurisdiction	\N
1007275	Belgorod	Belgorod	1002491	\N	Jurisdiction	\N
1007283	Republic of Karelia	Republic of Karelia	1002491	\N	Jurisdiction	\N
1007288	Nenetskiy Avtonomnyy Okrug	Nenetskiy Avtonomnyy Okrug	1002491	\N	Jurisdiction	\N
1007291	Kalmykiya	Kalmykiya	1002491	\N	Jurisdiction	\N
1007295	Krasnoyarskiy	Krasnoyarskiy	1002491	\N	Jurisdiction	\N
1007305	Tyva	Tyva	1002491	\N	Jurisdiction	\N
1007308	Khabarovsk Krai	Khabarovsk Krai	1002491	\N	Jurisdiction	\N
1006205	Zadarska	Zadarska	1002362	\N	Jurisdiction	\N
1006875	Baja California	Baja California	1002450	\N	Jurisdiction	\N
1007311	Transbaikal Territory	Transbaikal Territory	1002491	\N	Jurisdiction	\N
1007321	Al Mad??nah al Munawwarah	Al Madinah al Munawwarah	1002503	\N	Jurisdiction	\N
1007328	Min??aqat ???As??r	Mintaqat 'Asir	1002503	\N	Jurisdiction	\N
1007332	Ar Riy?????	Ar Riyad	1002503	\N	Jurisdiction	\N
1005357	Kabul	Kabul	1002312	\N	Jurisdiction	\N
1007341	White Nile	White Nile	1002520	\N	Jurisdiction	\N
1007348	Blue Nile	Blue Nile	1002520	\N	Jurisdiction	\N
1007352	Eastern Darfur	Eastern Darfur	1002520	\N	Jurisdiction	\N
1007357	Kronoberg	Kronoberg	1002524	\N	Jurisdiction	\N
1007360	J??nk??ping	Jonkoping	1002524	\N	Jurisdiction	\N
1007364	Uppsala	Uppsala	1002524	\N	Jurisdiction	\N
1007371	V??rmland	Varmland	1002524	\N	Jurisdiction	\N
1007374	Central Singapore	Central Singapore	1002508	\N	Jurisdiction	\N
1007379	Novo Mesto	Novo Mesto	1002511	\N	Jurisdiction	\N
1007388	Banskobystrick??	Banskobystricky	1002510	\N	Jurisdiction	\N
1007392	Tren??iansky	Trenciansky	1002510	\N	Jurisdiction	\N
1007396	Northern Province	Northern Province	1002507	\N	Jurisdiction	\N
1007401	Diourbel	Diourbel	1002504	\N	Jurisdiction	\N
1007405	Saint-Louis	Saint-Louis	1002504	\N	Jurisdiction	\N
1007412	Kaffrine	Kaffrine	1002504	\N	Jurisdiction	\N
1007416	Gedo	Gedo	1002513	\N	Jurisdiction	\N
1007419	Middle Shabele	Middle Shabele	1002513	\N	Jurisdiction	\N
1007423	Sanaag	Sanaag	1002513	\N	Jurisdiction	\N
1007426	Hiiraan	Hiiraan	1002513	\N	Jurisdiction	\N
1007430	Paramaribo	Paramaribo	1002521	\N	Jurisdiction	\N
1007438	Lakes	Lakes	1002517	\N	Jurisdiction	\N
1007441	S??o Tom?? Island	Sao Tome Island	1002502	\N	Jurisdiction	\N
1007446	Caba??as	Cabanas	1002375	\N	Jurisdiction	\N
1007449	San Miguel	San Miguel	1002375	\N	Jurisdiction	\N
1007453	La Uni??n	La Union	1002375	\N	Jurisdiction	\N
1007457	Hama	Hama	1002526	\N	Jurisdiction	\N
1007464	Latakia	Latakia	1002526	\N	Jurisdiction	\N
1007467	Ar-Raqqah	Ar-Raqqah	1002526	\N	Jurisdiction	\N
1007471	Manzini	Manzini	1002523	\N	Jurisdiction	\N
1007478	Chari-Baguirmi	Chari-Baguirmi	1002353	\N	Jurisdiction	\N
1007482	Hadjer-Lamis	Hadjer-Lamis	1002353	\N	Jurisdiction	\N
1007486	Logone Oriental	Logone Oriental	1002353	\N	Jurisdiction	\N
1007495	Prachuap Khiri Khan	Prachuap Khiri Khan	1002530	\N	Jurisdiction	\N
1007498	Nakhon Si Thammarat	Nakhon Si Thammarat	1002530	\N	Jurisdiction	\N
1007504	Sukhothai	Sukhothai	1002530	\N	Jurisdiction	\N
1007508	Phayao	Phayao	1002530	\N	Jurisdiction	\N
1007516	Changwat Udon Thani	Changwat Udon Thani	1002530	\N	Jurisdiction	\N
1007519	Samut Prakan	Samut Prakan	1002530	\N	Jurisdiction	\N
1007524	Ang Thong	Ang Thong	1002530	\N	Jurisdiction	\N
1007533	Chanthaburi	Chanthaburi	1002530	\N	Jurisdiction	\N
1007537	Suphan Buri	Suphan Buri	1002530	\N	Jurisdiction	\N
1007541	Changwat Bueng Kan	Changwat Bueng Kan	1002530	\N	Jurisdiction	\N
1007545	Samut Songkhram	Samut Songkhram	1002530	\N	Jurisdiction	\N
1007550	Buriram	Buriram	1002530	\N	Jurisdiction	\N
1007553	Phrae	Phrae	1002530	\N	Jurisdiction	\N
1007561	Nakhon Nayok	Nakhon Nayok	1002530	\N	Jurisdiction	\N
1007566	Khon Kaen	Khon Kaen	1002530	\N	Jurisdiction	\N
1007570	Viloyati Sughd	Viloyati Sughd	1002528	\N	Jurisdiction	\N
1007574	Cova Lima	Cova Lima	1002372	\N	Jurisdiction	\N
1007581	Laut??m	Lautem	1002372	\N	Jurisdiction	\N
1007584	Da??oguz	Dasoguz	1002536	\N	Jurisdiction	\N
1007589	Tawzar	Tawzar	1002534	\N	Jurisdiction	\N
1007595	Sily??nah	Silyanah	1002534	\N	Jurisdiction	\N
1007599	Al Mahd??yah	Al Mahdiyah	1002534	\N	Jurisdiction	\N
1007603	Q??bis	Qabis	1002534	\N	Jurisdiction	\N
1007610	Al Qayraw??n	Al Qayrawan	1002534	\N	Jurisdiction	\N
1007614	Mardin	Mardin	1002535	\N	Jurisdiction	\N
1007618	Isparta	Isparta	1002535	\N	Jurisdiction	\N
1007621	Mu??	Mus	1002535	\N	Jurisdiction	\N
1007628	Tunceli	Tunceli	1002535	\N	Jurisdiction	\N
1007631	Bitlis	Bitlis	1002535	\N	Jurisdiction	\N
1007635	Sivas	Sivas	1002535	\N	Jurisdiction	\N
1007646	Osmaniye	Osmaniye	1002535	\N	Jurisdiction	\N
1007650	K??r??ehir	Kirsehir	1002535	\N	Jurisdiction	\N
1007653	Adana	Adana	1002535	\N	Jurisdiction	\N
1007657	Karaman	Karaman	1002535	\N	Jurisdiction	\N
1007664	Zonguldak	Zonguldak	1002535	\N	Jurisdiction	\N
1005414	Buenos Aires	Buenos Aires	1002321	\N	Jurisdiction	\N
1005339	Escaldes-Engordany	Escaldes-Engordany	1002317	\N	Jurisdiction	\N
1005341	Umm al Qaywayn	Umm al Qaywayn	1002542	\N	Jurisdiction	\N
1005342	Ra??s al Khaymah	Ra??s al Khaymah	1002542	\N	Jurisdiction	\N
1005343	Ash Sh??riqah	Ash Shariqah	1002542	\N	Jurisdiction	\N
1005344	Dubai	Dubai	1002542	\N	Jurisdiction	\N
1005345	Al Fujayrah	Al Fujayrah	1002542	\N	Jurisdiction	\N
1005347	Ajman	Ajman	1002542	\N	Jurisdiction	\N
1005348	N??mr??z	Nimruz	1002312	\N	Jurisdiction	\N
1005349	Takh??r	Takhar	1002312	\N	Jurisdiction	\N
1005350	Herat	Herat	1002312	\N	Jurisdiction	\N
1005352	Ghowr	Ghowr	1002312	\N	Jurisdiction	\N
1005353	Sar-e Pol	Sar-e Pol	1002312	\N	Jurisdiction	\N
1005354	Samang??n	Samangan	1002312	\N	Jurisdiction	\N
1005355	Kunduz	Kunduz	1002312	\N	Jurisdiction	\N
1005479	????mkir	S??mkir	1002326	\N	Jurisdiction	\N
1005480	??amax??	Samaxi	1002326	\N	Jurisdiction	\N
1005483	Qusar	Qusar	1002326	\N	Jurisdiction	\N
1005484	Quba	Quba	1002326	\N	Jurisdiction	\N
1005486	Qazax	Qazax	1002326	\N	Jurisdiction	\N
1005489	Ab??eron	Abseron	1002326	\N	Jurisdiction	\N
1005490	G??y??ay	Goycay	1002326	\N	Jurisdiction	\N
1005491	G??nc??	G??nc??	1002326	\N	Jurisdiction	\N
1005493	B??rd??	B??rd??	1002326	\N	Jurisdiction	\N
1005495	A??da??	Agdas	1002326	\N	Jurisdiction	\N
1005498	Republika Srpska	Republika Srpska	1002339	\N	Jurisdiction	\N
1005499	Br??ko	Brcko	1002339	\N	Jurisdiction	\N
1005501	Rangpur Division	Rangpur Division	1002329	\N	Jurisdiction	\N
1005502	Chittagong	Chittagong	1002329	\N	Jurisdiction	\N
1005503	Dhaka	Dhaka	1002329	\N	Jurisdiction	\N
1005504	Sylhet	Sylhet	1002329	\N	Jurisdiction	\N
1005507	Baris??l	Barisal	1002329	\N	Jurisdiction	\N
1005508	Flanders	Flanders	1002332	\N	Jurisdiction	\N
1005510	Brussels Capital	Brussels Capital	1002332	\N	Jurisdiction	\N
1005512	Nord	Nord	1002345	\N	Jurisdiction	\N
1005514	Centre-Est	Centre-Est	1002345	\N	Jurisdiction	\N
1005515	Centre-Ouest	Centre-Ouest	1002345	\N	Jurisdiction	\N
1005516	Centre-Sud	Centre-Sud	1002345	\N	Jurisdiction	\N
1005517	Centre	Centre	1002345	\N	Jurisdiction	\N
1005520	Est	Est	1002345	\N	Jurisdiction	\N
1005521	Sahel	Sahel	1002345	\N	Jurisdiction	\N
1005523	Southwest	Southwest	1002345	\N	Jurisdiction	\N
1005524	Yambol	Yambol	1002344	\N	Jurisdiction	\N
1005527	Pazardzhik	Pazardzhik	1002344	\N	Jurisdiction	\N
1005529	Varna	Varna	1002344	\N	Jurisdiction	\N
1005531	Lovech	Lovech	1002344	\N	Jurisdiction	\N
1005532	Dobrich	Dobrich	1002344	\N	Jurisdiction	\N
1005534	Stara Zagora	Stara Zagora	1002344	\N	Jurisdiction	\N
1005535	Kyustendil	Kyustendil	1002344	\N	Jurisdiction	\N
1005537	Smolyan	Smolyan	1002344	\N	Jurisdiction	\N
1005539	Silistra	Silistra	1002344	\N	Jurisdiction	\N
1005540	Shumen	Shumen	1002344	\N	Jurisdiction	\N
1005542	Blagoevgrad	Blagoevgrad	1002344	\N	Jurisdiction	\N
1005545	Razgrad	Razgrad	1002344	\N	Jurisdiction	\N
1005546	Plovdiv	Plovdiv	1002344	\N	Jurisdiction	\N
1005547	Pleven	Pleven	1002344	\N	Jurisdiction	\N
1005550	K??rdzhali	Kurdzhali	1002344	\N	Jurisdiction	\N
1005552	Manama	Manama	1002328	\N	Jurisdiction	\N
1005555	Muharraq	Muharraq	1002328	\N	Jurisdiction	\N
1005558	Bujumbura Mairie	Bujumbura Mairie	1002346	\N	Jurisdiction	\N
1005559	Muramvya	Muramvya	1002346	\N	Jurisdiction	\N
1005560	Gitega	Gitega	1002346	\N	Jurisdiction	\N
1005562	Ngozi	Ngozi	1002346	\N	Jurisdiction	\N
1005563	Kayanza	Kayanza	1002346	\N	Jurisdiction	\N
1005566	Borgou	Borgou	1002334	\N	Jurisdiction	\N
1005568	Collines	Collines	1002334	\N	Jurisdiction	\N
1005569	Plateau	Plateau	1002334	\N	Jurisdiction	\N
1005572	Mono	Mono	1002334	\N	Jurisdiction	\N
1005573	Alibori	Alibori	1002334	\N	Jurisdiction	\N
1005574	Kouffo	Kouffo	1002334	\N	Jurisdiction	\N
1005576	Zou	Zou	1002334	\N	Jurisdiction	\N
1005579	Tutong	Tutong	1002343	\N	Jurisdiction	\N
1005580	Belait	Belait	1002343	\N	Jurisdiction	\N
1005582	Tarija	Tarija	1002337	\N	Jurisdiction	\N
1005584	Potos??	Potosi	1002337	\N	Jurisdiction	\N
1005585	El Beni	El Beni	1002337	\N	Jurisdiction	\N
1005587	Cochabamba	Cochabamba	1002337	\N	Jurisdiction	\N
1005588	Oruro	Oruro	1002337	\N	Jurisdiction	\N
1005590	Pando	Pando	1002337	\N	Jurisdiction	\N
1005592	Maranh??o	Maranhao	1002341	\N	Jurisdiction	\N
1005595	Para??ba	Paraiba	1002341	\N	Jurisdiction	\N
1005596	Cear??	Ceara	1002341	\N	Jurisdiction	\N
1005598	Piau??	Piaui	1002341	\N	Jurisdiction	\N
1005600	Amap??	Amapa	1002341	\N	Jurisdiction	\N
1005603	Tocantins	Tocantins	1002341	\N	Jurisdiction	\N
1005605	S??o Paulo	Sao Paulo	1002341	\N	Jurisdiction	\N
1005606	Rio de Janeiro	Rio de Janeiro	1002341	\N	Jurisdiction	\N
1005609	Rio Grande do Sul	Rio Grande do Sul	1002341	\N	Jurisdiction	\N
1005610	Paran??	Parana	1002341	\N	Jurisdiction	\N
1005611	Mato Grosso	Mato Grosso	1002341	\N	Jurisdiction	\N
1005612	Goi??s	Goias	1002341	\N	Jurisdiction	\N
1005614	Sergipe	Sergipe	1002341	\N	Jurisdiction	\N
1005616	Acre	Acre	1002341	\N	Jurisdiction	\N
1005618	Roraima	Roraima	1002341	\N	Jurisdiction	\N
1005619	New Providence	New Providence	1002327	\N	Jurisdiction	\N
1005620	Freeport	Freeport	1002327	\N	Jurisdiction	\N
1005623	Chukha District	Chukha District	1002336	\N	Jurisdiction	\N
1005625	Central	Central	1002340	\N	Jurisdiction	\N
1005626	Kweneng	Kweneng	1002340	\N	Jurisdiction	\N
1005629	Kgatleng	Kgatleng	1002340	\N	Jurisdiction	\N
1005630	North West	North West	1002340	\N	Jurisdiction	\N
1005637	Mogilev	Mogilev	1002331	\N	Jurisdiction	\N
1005638	Minsk City	Minsk City	1002331	\N	Jurisdiction	\N
1005639	Cayo	Cayo	1002333	\N	Jurisdiction	\N
1005643	Alberta	Alberta	1002349	\N	Jurisdiction	\N
1005644	Ontario	Ontario	1002349	\N	Jurisdiction	\N
1005645	Quebec	Quebec	1002349	\N	Jurisdiction	\N
1005648	Newfoundland and Labrador	Newfoundland and Labrador	1002349	\N	Jurisdiction	\N
1005649	Nova Scotia	Nova Scotia	1002349	\N	Jurisdiction	\N
1005650	New Brunswick	New Brunswick	1002349	\N	Jurisdiction	\N
1005652	Yukon	Yukon	1002349	\N	Jurisdiction	\N
1005654	Eastern Province	Eastern Province	1002367	\N	Jurisdiction	\N
1005655	South Kivu	South Kivu	1002367	\N	Jurisdiction	\N
1005657	Nord Kivu	Nord Kivu	1002367	\N	Jurisdiction	\N
1005659	??quateur	Equateur	1002367	\N	Jurisdiction	\N
1005660	Katanga	Katanga	1002367	\N	Jurisdiction	\N
1005661	Maniema	Maniema	1002367	\N	Jurisdiction	\N
1005663	Bandundu	Bandundu	1002367	\N	Jurisdiction	\N
1005665	Basse-Kotto	Basse-Kotto	1002352	\N	Jurisdiction	\N
1005667	Haute-Kotto	Haute-Kotto	1002352	\N	Jurisdiction	\N
1005668	Mbomou	Mbomou	1002352	\N	Jurisdiction	\N
1005670	Ouham-Pend??	Ouham-Pende	1002352	\N	Jurisdiction	\N
1005672	Lobaye	Lobaye	1002352	\N	Jurisdiction	\N
1005674	Ombella-Mpoko	Ombella-Mpoko	1002352	\N	Jurisdiction	\N
1005675	Mamb??r??-Kad????	Mambere-Kadei	1002352	\N	Jurisdiction	\N
1005677	Ouham	Ouham	1002352	\N	Jurisdiction	\N
1005679	L??koumou	Lekoumou	1002488	\N	Jurisdiction	\N
1005681	Cuvette	Cuvette	1002488	\N	Jurisdiction	\N
1005682	Sangha	Sangha	1002488	\N	Jurisdiction	\N
1005683	Niari	Niari	1002488	\N	Jurisdiction	\N
1005686	Plateaux	Plateaux	1002488	\N	Jurisdiction	\N
1005687	Brazzaville	Brazzaville	1002488	\N	Jurisdiction	\N
1005688	Zurich	Zurich	1002525	\N	Jurisdiction	\N
1005692	Aargau	Aargau	1002525	\N	Jurisdiction	\N
1005693	Geneva	Geneva	1002525	\N	Jurisdiction	\N
1005694	Bern	Bern	1002525	\N	Jurisdiction	\N
1005697	Solothurn	Solothurn	1002525	\N	Jurisdiction	\N
1005699	Basel-Landschaft	Basel-Landschaft	1002525	\N	Jurisdiction	\N
1005700	Lucerne	Lucerne	1002525	\N	Jurisdiction	\N
1005701	Ticino	Ticino	1002525	\N	Jurisdiction	\N
1005704	Fribourg	Fribourg	1002525	\N	Jurisdiction	\N
1005705	Grisons	Grisons	1002525	\N	Jurisdiction	\N
1005707	Marahou??	Marahoue	1002417	\N	Jurisdiction	\N
1005708	Lacs	Lacs	1002417	\N	Jurisdiction	\N
1005711	Savanes	Savanes	1002417	\N	Jurisdiction	\N
1005712	Lagunes	Lagunes	1002417	\N	Jurisdiction	\N
1005713	Zanzan	Zanzan	1002417	\N	Jurisdiction	\N
1005716	Fromager	Fromager	1002417	\N	Jurisdiction	\N
1005717	Dengu??l??	Denguele	1002417	\N	Jurisdiction	\N
1005719	Dix-Huit Montagnes	Dix-Huit Montagnes	1002417	\N	Jurisdiction	\N
1005720	Sud-Bandama	Sud-Bandama	1002417	\N	Jurisdiction	\N
1005723	Moyen-Como??	Moyen-Comoe	1002417	\N	Jurisdiction	\N
1005724	Agn??by	Agneby	1002417	\N	Jurisdiction	\N
1005726	Araucan??a	Araucania	1002354	\N	Jurisdiction	\N
1005727	Atacama	Atacama	1002354	\N	Jurisdiction	\N
1005728	Los R??os	Los Rios	1002354	\N	Jurisdiction	\N
1005731	Maule	Maule	1002354	\N	Jurisdiction	\N
1005733	O'Higgins	O'Higgins	1002354	\N	Jurisdiction	\N
1005734	Magallanes	Magallanes	1002354	\N	Jurisdiction	\N
1005736	Ais??n	Aisen	1002354	\N	Jurisdiction	\N
1005738	Tarapac??	Tarapaca	1002354	\N	Jurisdiction	\N
1005739	Arica y Parinacota	Arica y Parinacota	1002354	\N	Jurisdiction	\N
1005740	Centre	Centre	1002348	\N	Jurisdiction	\N
1005743	West	West	1002348	\N	Jurisdiction	\N
1005745	Adamaoua	Adamaoua	1002348	\N	Jurisdiction	\N
1005746	North Province	North Province	1002348	\N	Jurisdiction	\N
1005747	South Province	South Province	1002348	\N	Jurisdiction	\N
1005749	East	East	1002348	\N	Jurisdiction	\N
1005751	Gansu Sheng	Gansu Sheng	1002355	\N	Jurisdiction	\N
1005752	Xinjiang Uygur Zizhiqu	Xinjiang Uygur Zizhiqu	1002355	\N	Jurisdiction	\N
1005755	Sichuan	Sichuan	1002355	\N	Jurisdiction	\N
1005756	Hunan	Hunan	1002355	\N	Jurisdiction	\N
1005757	Henan Sheng	Henan Sheng	1002355	\N	Jurisdiction	\N
1005759	Zhejiang Sheng	Zhejiang Sheng	1002355	\N	Jurisdiction	\N
1005761	Jiangsu	Jiangsu	1002355	\N	Jurisdiction	\N
1005764	Guangdong	Guangdong	1002355	\N	Jurisdiction	\N
1005765	Hebei	Hebei	1002355	\N	Jurisdiction	\N
1005766	Fujian	Fujian	1002355	\N	Jurisdiction	\N
1005770	Chongqing Shi	Chongqing Shi	1002355	\N	Jurisdiction	\N
1005771	Anhui Sheng	Anhui Sheng	1002355	\N	Jurisdiction	\N
1005772	Ningxia Huizu Zizhiqu	Ningxia Huizu Zizhiqu	1002355	\N	Jurisdiction	\N
1005773	Jiangxi Sheng	Jiangxi Sheng	1002355	\N	Jurisdiction	\N
1005775	Hainan	Hainan	1002355	\N	Jurisdiction	\N
1005777	Inner Mongolia	Inner Mongolia	1002355	\N	Jurisdiction	\N
1005778	Beijing	Beijing	1002355	\N	Jurisdiction	\N
1005781	Cundinamarca	Cundinamarca	1002358	\N	Jurisdiction	\N
1005782	Valle del Cauca	Valle del Cauca	1002358	\N	Jurisdiction	\N
1005784	Casanare	Casanare	1002358	\N	Jurisdiction	\N
1005785	Caldas	Caldas	1002358	\N	Jurisdiction	\N
1005788	La Guajira	La Guajira	1002358	\N	Jurisdiction	\N
1005789	Cesar	Cesar	1002358	\N	Jurisdiction	\N
1005791	Nari??o	Narino	1002358	\N	Jurisdiction	\N
1005793	Sucre	Sucre	1002358	\N	Jurisdiction	\N
1005794	C??rdoba	Cordoba	1002358	\N	Jurisdiction	\N
1005796	Atl??ntico	Atlantico	1002358	\N	Jurisdiction	\N
1005799	Cauca	Cauca	1002358	\N	Jurisdiction	\N
1005800	Magdalena	Magdalena	1002358	\N	Jurisdiction	\N
1005802	Quind??o	Quindio	1002358	\N	Jurisdiction	\N
1005803	Choc??	Choco	1002358	\N	Jurisdiction	\N
1005805	Huila	Huila	1002358	\N	Jurisdiction	\N
1005806	Tolima	Tolima	1002358	\N	Jurisdiction	\N
1005807	Amazonas	Amazonas	1002358	\N	Jurisdiction	\N
1005809	Bogota D.C.	Bogota D.C.	1002358	\N	Jurisdiction	\N
1005810	Guaviare	Guaviare	1002358	\N	Jurisdiction	\N
1005812	San Jos??	San Jose	1002361	\N	Jurisdiction	\N
1005813	Lim??n	Limon	1002361	\N	Jurisdiction	\N
1005816	Puntarenas	Puntarenas	1002361	\N	Jurisdiction	\N
1005817	Guanacaste	Guanacaste	1002361	\N	Jurisdiction	\N
1005820	Pinar del R??o	Pinar del Rio	1002363	\N	Jurisdiction	\N
1005822	Ciego de ??vila	Ciego de Avila	1002363	\N	Jurisdiction	\N
1005824	Holgu??n	Holguin	1002363	\N	Jurisdiction	\N
1006010	Luxor	Luxor	1002374	\N	Jurisdiction	\N
1005826	La Habana	La Habana	1002363	\N	Jurisdiction	\N
1005827	Santiago de Cuba	Santiago de Cuba	1002363	\N	Jurisdiction	\N
1005830	Cienfuegos	Cienfuegos	1002363	\N	Jurisdiction	\N
1005831	Guant??namo	Guantanamo	1002363	\N	Jurisdiction	\N
1005832	Las Tunas	Las Tunas	1002363	\N	Jurisdiction	\N
1005834	Sal	Sal	1002350	\N	Jurisdiction	\N
1005836	S??o Vicente	Sao Vicente	1002350	\N	Jurisdiction	\N
1005838	Ammochostos	Ammochostos	1002365	\N	Jurisdiction	\N
1005839	Pafos	Pafos	1002365	\N	Jurisdiction	\N
1005841	Limassol	Limassol	1002365	\N	Jurisdiction	\N
1005842	Larnaka	Larnaka	1002365	\N	Jurisdiction	\N
1005844	Kr??lov??hradeck??	Kralovehradecky	1002366	\N	Jurisdiction	\N
1005846	Zl??n	Zlin	1002366	\N	Jurisdiction	\N
1005848	??steck??	Ustecky	1002366	\N	Jurisdiction	\N
1005849	Pardubick??	Pardubicky	1002366	\N	Jurisdiction	\N
1005851	Jiho??esk??	Jihocesky	1002366	\N	Jurisdiction	\N
1005852	Olomouck??	Olomoucky	1002366	\N	Jurisdiction	\N
1005855	Praha	Praha	1002366	\N	Jurisdiction	\N
1005856	Plze??sk??	Plzensky	1002366	\N	Jurisdiction	\N
1005857	Libereck??	Liberecky	1002366	\N	Jurisdiction	\N
1005858	Saxony	Saxony	1002391	\N	Jurisdiction	\N
1005861	Brandenburg	Brandenburg	1002391	\N	Jurisdiction	\N
1005862	Bavaria	Bavaria	1002391	\N	Jurisdiction	\N
1005864	Berlin	Berlin	1002391	\N	Jurisdiction	\N
1005865	Lower Saxony	Lower Saxony	1002391	\N	Jurisdiction	\N
1005866	Hesse	Hesse	1002391	\N	Jurisdiction	\N
1005869	Baden-W??rttemberg	Baden-Wurttemberg	1002391	\N	Jurisdiction	\N
1005870	Thuringia	Thuringia	1002391	\N	Jurisdiction	\N
1005872	Saarland	Saarland	1002391	\N	Jurisdiction	\N
1005874	Tadjourah	Tadjourah	1002369	\N	Jurisdiction	\N
1005876	Djibouti	Djibouti	1002369	\N	Jurisdiction	\N
1005878	Central Jutland	Central Jutland	1002368	\N	Jurisdiction	\N
1005881	Zealand	Zealand	1002368	\N	Jurisdiction	\N
1005882	North Denmark	North Denmark	1002368	\N	Jurisdiction	\N
1005883	Saint George	Saint George	1002370	\N	Jurisdiction	\N
1005884	Nacional	Nacional	1002371	\N	Jurisdiction	\N
1005887	El Se??bo	El Seibo	1002371	\N	Jurisdiction	\N
1005888	Barahona	Barahona	1002371	\N	Jurisdiction	\N
1005890	San Juan	San Juan	1002371	\N	Jurisdiction	\N
1005892	Duarte	Duarte	1002371	\N	Jurisdiction	\N
1005894	Puerto Plata	Puerto Plata	1002371	\N	Jurisdiction	\N
1005895	La Altagracia	La Altagracia	1002371	\N	Jurisdiction	\N
1005896	Hermanas Mirabal	Hermanas Mirabal	1002371	\N	Jurisdiction	\N
1005898	Monte Plata	Monte Plata	1002371	\N	Jurisdiction	\N
1005899	Baoruco	Baoruco	1002371	\N	Jurisdiction	\N
1005901	Espaillat	Espaillat	1002371	\N	Jurisdiction	\N
1005903	La Romana	La Romana	1002371	\N	Jurisdiction	\N
1005904	La Vega	La Vega	1002371	\N	Jurisdiction	\N
1005905	Hato Mayor	Hato Mayor	1002371	\N	Jurisdiction	\N
1005908	Monse??or Nouel	Monsenor Nouel	1002371	\N	Jurisdiction	\N
1005909	Santo Domingo	Santo Domingo	1002371	\N	Jurisdiction	\N
1005911	Azua	Azua	1002371	\N	Jurisdiction	\N
1005912	Boumerdes	Boumerdes	1002315	\N	Jurisdiction	\N
1005913	Biskra	Biskra	1002315	\N	Jurisdiction	\N
1005916	Ouargla	Ouargla	1002315	\N	Jurisdiction	\N
1005918	Tizi Ouzou	Tizi Ouzou	1002315	\N	Jurisdiction	\N
1005919	Tissemsilt	Tissemsilt	1002315	\N	Jurisdiction	\N
1005920	Tindouf	Tindouf	1002315	\N	Jurisdiction	\N
1005925	Mila	Mila	1002315	\N	Jurisdiction	\N
1005926	T??bessa	Tebessa	1002315	\N	Jurisdiction	\N
1005927	Batna	Batna	1002315	\N	Jurisdiction	\N
1005930	Bouira	Bouira	1002315	\N	Jurisdiction	\N
1005931	Blida	Blida	1002315	\N	Jurisdiction	\N
1005933	Mascara	Mascara	1002315	\N	Jurisdiction	\N
1005934	Oran	Oran	1002315	\N	Jurisdiction	\N
1005937	M??sila	M??sila	1002315	\N	Jurisdiction	\N
1005938	S??tif	Setif	1002315	\N	Jurisdiction	\N
1005939	Sa??da	Saida	1002315	\N	Jurisdiction	\N
1005943	Oum el Bouaghi	Oum el Bouaghi	1002315	\N	Jurisdiction	\N
1005944	Mostaganem	Mostaganem	1002315	\N	Jurisdiction	\N
1005945	Gharda??a	Ghardaia	1002315	\N	Jurisdiction	\N
1005947	M??d??a	Medea	1002315	\N	Jurisdiction	\N
1005949	Khenchela	Khenchela	1002315	\N	Jurisdiction	\N
1005950	Jijel	Jijel	1002315	\N	Jurisdiction	\N
1005953	Constantine	Constantine	1002315	\N	Jurisdiction	\N
1005954	El Tarf	El Tarf	1002315	\N	Jurisdiction	\N
1005955	Annaba	Annaba	1002315	\N	Jurisdiction	\N
1005960	Guayas	Guayas	1002373	\N	Jurisdiction	\N
1005961	Los R??os	Los Rios	1002373	\N	Jurisdiction	\N
1005962	Carchi	Carchi	1002373	\N	Jurisdiction	\N
1005964	Manab??	Manabi	1002373	\N	Jurisdiction	\N
1005966	El Oro	El Oro	1002373	\N	Jurisdiction	\N
1005968	Esmeraldas	Esmeraldas	1002373	\N	Jurisdiction	\N
1005969	Chimborazo	Chimborazo	1002373	\N	Jurisdiction	\N
1005970	Pichincha	Pichincha	1002373	\N	Jurisdiction	\N
1005973	Orellana	Orellana	1002373	\N	Jurisdiction	\N
1005974	Tungurahua	Tungurahua	1002373	\N	Jurisdiction	\N
1005976	Morona-Santiago	Morona-Santiago	1002373	\N	Jurisdiction	\N
1005977	Loja	Loja	1002373	\N	Jurisdiction	\N
1005980	Bol??var	Bolivar	1002373	\N	Jurisdiction	\N
1005981	Azuay	Azuay	1002373	\N	Jurisdiction	\N
1005984	Harjumaa	Harjumaa	1002378	\N	Jurisdiction	\N
1005985	Ida-Virumaa	Ida-Virumaa	1002378	\N	Jurisdiction	\N
1005987	P??rnumaa	Parnumaa	1002378	\N	Jurisdiction	\N
1005990	Mu?????faz??at al Fayy??m	Muhafaz??at al Fayyum	1002374	\N	Jurisdiction	\N
1005991	Mu?????faz??at ad Daqahl??yah	Muhafaz??at ad Daqahliyah	1002374	\N	Jurisdiction	\N
1005992	Mu?????faz??at al Min??f??yah	Muhafaz??at al Minufiyah	1002374	\N	Jurisdiction	\N
1005993	S??h??j	Suhaj	1002374	\N	Jurisdiction	\N
1005994	Mu?????faz??at Ban?? Suwayf	Muhafaz??at Bani Suwayf	1002374	\N	Jurisdiction	\N
1005995	Kafr ash Shaykh	Kafr ash Shaykh	1002374	\N	Jurisdiction	\N
1005997	Al Bu???ayrah	Al Buhayrah	1002374	\N	Jurisdiction	\N
1005998	Red Sea	Red Sea	1002374	\N	Jurisdiction	\N
1005999	Qin??	Qina	1002374	\N	Jurisdiction	\N
1006002	Asy????	Asyut	1002374	\N	Jurisdiction	\N
1006003	Al J??zah	Al Jizah	1002374	\N	Jurisdiction	\N
1006004	Asw??n	Aswan	1002374	\N	Jurisdiction	\N
1006006	Dumy????	Dumyat	1002374	\N	Jurisdiction	\N
1006009	As Suways	As Suways	1002374	\N	Jurisdiction	\N
1006011	Mu?????faz??at al W??d?? al Jad??d	Muhafaz??at al Wadi al Jadid	1002374	\N	Jurisdiction	\N
1006012	Alexandria	Alexandria	1002374	\N	Jurisdiction	\N
1006014	Oued Ed-Dahab-Lagouira	Oued Ed-Dahab-Lagouira	1002552	\N	Jurisdiction	\N
1006015	Northern Red Sea Region	Northern Red Sea Region	1002377	\N	Jurisdiction	\N
1006016	??nseba	Anseba	1002377	\N	Jurisdiction	\N
1006019	Debubaw?? K??eyih Bahr??	Debubawi K??eyih Bahri	1002377	\N	Jurisdiction	\N
1006020	Debub	Debub	1002377	\N	Jurisdiction	\N
1006021	Andalusia	Andalusia	1002518	\N	Jurisdiction	\N
1006023	Murcia	Murcia	1002518	\N	Jurisdiction	\N
1006026	Canary Islands	Canary Islands	1002518	\N	Jurisdiction	\N
1006027	Balearic Islands	Balearic Islands	1002518	\N	Jurisdiction	\N
1006028	Melilla	Melilla	1002518	\N	Jurisdiction	\N
1006030	Aragon	Aragon	1002518	\N	Jurisdiction	\N
1006032	Galicia	Galicia	1002518	\N	Jurisdiction	\N
1006033	Madrid	Madrid	1002518	\N	Jurisdiction	\N
1006034	Catalonia	Catalonia	1002518	\N	Jurisdiction	\N
1006037	Asturias	Asturias	1002518	\N	Jurisdiction	\N
1006039	Ceuta	Ceuta	1002518	\N	Jurisdiction	\N
1006040	Oromiya	Oromiya	1002379	\N	Jurisdiction	\N
1006042	Amhara	Amhara	1002379	\N	Jurisdiction	\N
1006044	Somali	Somali	1002379	\N	Jurisdiction	\N
1006045	Harari	Harari	1002379	\N	Jurisdiction	\N
1006046	Gambela	Gambela	1002379	\N	Jurisdiction	\N
1006048	Dire Dawa	Dire Dawa	1002379	\N	Jurisdiction	\N
1006050	??d??s ??beba	Adis Abeba	1002379	\N	Jurisdiction	\N
1006051	Pirkanmaa	Pirkanmaa	1002383	\N	Jurisdiction	\N
1006053	Northern Savo	Northern Savo	1002383	\N	Jurisdiction	\N
1006055	Southwest Finland	Southwest Finland	1002383	\N	Jurisdiction	\N
1006056	Lapland	Lapland	1002383	\N	Jurisdiction	\N
1006059	H??me	Hame	1002383	\N	Jurisdiction	\N
1006060	Satakunta	Satakunta	1002383	\N	Jurisdiction	\N
1006776	Bitola	Bitola	1002438	\N	Jurisdiction	\N
1006062	Central Finland	Central Finland	1002383	\N	Jurisdiction	\N
1006065	Kymenlaakso	Kymenlaakso	1002383	\N	Jurisdiction	\N
1006066	Central Ostrobothnia	Central Ostrobothnia	1002383	\N	Jurisdiction	\N
1006067	Kainuu	Kainuu	1002383	\N	Jurisdiction	\N
1006069	Central	Central	1002382	\N	Jurisdiction	\N
1006070	Western	Western	1002382	\N	Jurisdiction	\N
1006073	Streymoy	Streymoy	1002381	\N	Jurisdiction	\N
1006074	??le-de-France	Ile-de-France	1002384	\N	Jurisdiction	\N
1006077	Auvergne-Rh??ne-Alpes	Auvergne-Rhone-Alpes	1002384	\N	Jurisdiction	\N
1006078	Provence-Alpes-C??te d'Azur	Provence-Alpes-Cote d'Azur	1002384	\N	Jurisdiction	\N
1006079	Brittany	Brittany	1002384	\N	Jurisdiction	\N
1006457	Nara	Nara	1002419	\N	Jurisdiction	\N
1006083	Pays de la Loire	Pays de la Loire	1002384	\N	Jurisdiction	\N
1006084	Normandy	Normandy	1002384	\N	Jurisdiction	\N
1006086	Corsica	Corsica	1002384	\N	Jurisdiction	\N
1006087	Nyanga	Nyanga	1002388	\N	Jurisdiction	\N
1006089	Woleu-Ntem	Woleu-Ntem	1002388	\N	Jurisdiction	\N
1006090	Ngouni??	Ngounie	1002388	\N	Jurisdiction	\N
1006091	Haut-Ogoou??	Haut-Ogooue	1002388	\N	Jurisdiction	\N
1006092	Estuaire	Estuaire	1002388	\N	Jurisdiction	\N
1006095	England	England	1002543	\N	Jurisdiction	\N
1006096	Wales	Wales	1002543	\N	Jurisdiction	\N
1006098	Northern Ireland	Northern Ireland	1002543	\N	Jurisdiction	\N
1006099	Saint George	Saint George	1002396	\N	Jurisdiction	\N
1006101	Imereti	Imereti	1002390	\N	Jurisdiction	\N
1006103	Abkhazia	Abkhazia	1002390	\N	Jurisdiction	\N
1006104	Kakheti	Kakheti	1002390	\N	Jurisdiction	\N
1006105	T'bilisi	T'bilisi	1002390	\N	Jurisdiction	\N
1006107	Guria	Guria	1002390	\N	Jurisdiction	\N
1006109	Samtskhe-Javakheti	Samtskhe-Javakheti	1002390	\N	Jurisdiction	\N
1006110	Guyane	Guyane	1002385	\N	Jurisdiction	\N
1006112	Northern	Northern	1002392	\N	Jurisdiction	\N
1006114	Brong-Ahafo	Brong-Ahafo	1002392	\N	Jurisdiction	\N
1006116	Greater Accra	Greater Accra	1002392	\N	Jurisdiction	\N
1006117	Western	Western	1002392	\N	Jurisdiction	\N
1006885	Chihuahua	Chihuahua	1002450	\N	Jurisdiction	\N
1006120	Upper East	Upper East	1002392	\N	Jurisdiction	\N
1006121	Volta	Volta	1002392	\N	Jurisdiction	\N
1006123	Western	Western	1002389	\N	Jurisdiction	\N
1006125	Banjul	Banjul	1002389	\N	Jurisdiction	\N
1006127	Kindia	Kindia	1002401	\N	Jurisdiction	\N
1006128	Kankan	Kankan	1002401	\N	Jurisdiction	\N
1006131	Faranah	Faranah	1002401	\N	Jurisdiction	\N
1006132	Boke	Boke	1002401	\N	Jurisdiction	\N
1006133	Conakry	Conakry	1002401	\N	Jurisdiction	\N
1006136	Bioko Norte	Bioko Norte	1002376	\N	Jurisdiction	\N
1006138	Attica	Attica	1002394	\N	Jurisdiction	\N
1006139	Thessaly	Thessaly	1002394	\N	Jurisdiction	\N
1006142	Crete	Crete	1002394	\N	Jurisdiction	\N
1006143	Epirus	Epirus	1002394	\N	Jurisdiction	\N
1006145	North Aegean	North Aegean	1002394	\N	Jurisdiction	\N
1006146	South Aegean	South Aegean	1002394	\N	Jurisdiction	\N
1006149	West Macedonia	West Macedonia	1002394	\N	Jurisdiction	\N
1006150	Ionian Islands	Ionian Islands	1002394	\N	Jurisdiction	\N
1006151	Zacapa	Zacapa	1002399	\N	Jurisdiction	\N
1006152	Guatemala	Guatemala	1002399	\N	Jurisdiction	\N
1006154	Chimaltenango	Chimaltenango	1002399	\N	Jurisdiction	\N
1006156	Solol??	Solola	1002399	\N	Jurisdiction	\N
1006158	Quich??	Quiche	1002399	\N	Jurisdiction	\N
1006159	San Marcos	San Marcos	1002399	\N	Jurisdiction	\N
1006161	Alta Verapaz	Alta Verapaz	1002399	\N	Jurisdiction	\N
1006162	Pet??n	Peten	1002399	\N	Jurisdiction	\N
1006165	Retalhuleu	Retalhuleu	1002399	\N	Jurisdiction	\N
1006166	Quetzaltenango	Quetzaltenango	1002399	\N	Jurisdiction	\N
1006168	Jutiapa	Jutiapa	1002399	\N	Jurisdiction	\N
1006171	Chiquimula	Chiquimula	1002399	\N	Jurisdiction	\N
1006173	Tamuning	Tamuning	1002398	\N	Jurisdiction	\N
1006174	Yigo	Yigo	1002398	\N	Jurisdiction	\N
1006175	Hagatna	Hagatna	1002398	\N	Jurisdiction	\N
1006176	Dededo	Dededo	1002398	\N	Jurisdiction	\N
1006179	Bafat??	Bafata	1002402	\N	Jurisdiction	\N
1006182	Demerara-Mahaica	Demerara-Mahaica	1002403	\N	Jurisdiction	\N
1006183	Tsuen Wan	Tsuen Wan	1002406	\N	Jurisdiction	\N
1006184	Yuen Long	Yuen Long	1002406	\N	Jurisdiction	\N
1006186	Tai Po	Tai Po	1002406	\N	Jurisdiction	\N
1006187	Sha Tin	Sha Tin	1002406	\N	Jurisdiction	\N
1006189	Central and Western	Central and Western	1002406	\N	Jurisdiction	\N
1006190	Cort??s	Cortes	1002405	\N	Jurisdiction	\N
1006192	Col??n	Colon	1002405	\N	Jurisdiction	\N
1006194	Francisco Moraz??n	Francisco Morazan	1002405	\N	Jurisdiction	\N
1006195	Comayagua	Comayagua	1002405	\N	Jurisdiction	\N
1006198	Valle	Valle	1002405	\N	Jurisdiction	\N
1006199	La Paz	La Paz	1002405	\N	Jurisdiction	\N
1006200	Olancho	Olancho	1002405	\N	Jurisdiction	\N
1006204	Grad Zagreb	Grad Zagreb	1002362	\N	Jurisdiction	\N
1006208	Vara??dinska	Varazdinska	1002362	\N	Jurisdiction	\N
1006209	Splitsko-Dalmatinska	Splitsko-Dalmatinska	1002362	\N	Jurisdiction	\N
1006210	Brodsko-Posavska	Brodsko-Posavska	1002362	\N	Jurisdiction	\N
1006211	Po??e??ko-Slavonska	Pozesko-Slavonska	1002362	\N	Jurisdiction	\N
1006212	Sisa??ko-Moslava??ka	Sisacko-Moslavacka	1002362	\N	Jurisdiction	\N
1006216	Osje??ko-Baranjska	Osjecko-Baranjska	1002362	\N	Jurisdiction	\N
1006218	Karlova??ka	Karlovacka	1002362	\N	Jurisdiction	\N
1006219	Dubrova??ko-Neretvanska	Dubrovacko-Neretvanska	1002362	\N	Jurisdiction	\N
1006220	Me??imurska	Medimurska	1002362	\N	Jurisdiction	\N
1006222	Artibonite	Artibonite	1002404	\N	Jurisdiction	\N
1006223	Ouest	Ouest	1002404	\N	Jurisdiction	\N
1006224	Nord	Nord	1002404	\N	Jurisdiction	\N
1006226	Nippes	Nippes	1002404	\N	Jurisdiction	\N
1006227	Grand??Anse	Grand??Anse	1002404	\N	Jurisdiction	\N
1006232	Borsod-Aba??j-Zempl??n	Borsod-Abauj-Zemplen	1002407	\N	Jurisdiction	\N
1006233	Csongr??d	Csongrad	1002407	\N	Jurisdiction	\N
1006234	Bekes	Bekes	1002407	\N	Jurisdiction	\N
1006237	Heves	Heves	1002407	\N	Jurisdiction	\N
1006238	Pest	Pest	1002407	\N	Jurisdiction	\N
1006239	Zala	Zala	1002407	\N	Jurisdiction	\N
1006240	Veszpr??m	Veszprem	1002407	\N	Jurisdiction	\N
1006242	Vas	Vas	1002407	\N	Jurisdiction	\N
1006244	Fej??r	Fejer	1002407	\N	Jurisdiction	\N
1006246	Somogy	Somogy	1002407	\N	Jurisdiction	\N
1006247	N??gr??d	Nograd	1002407	\N	Jurisdiction	\N
1007042	Panam??	Panama	1002478	\N	Jurisdiction	\N
1006249	B??cs-Kiskun	Bacs-Kiskun	1002407	\N	Jurisdiction	\N
1006252	Aceh	Aceh	1002410	\N	Jurisdiction	\N
1006254	Central Java	Central Java	1002410	\N	Jurisdiction	\N
1006255	East Java	East Java	1002410	\N	Jurisdiction	\N
1006256	West Java	West Java	1002410	\N	Jurisdiction	\N
1006258	East Nusa Tenggara	East Nusa Tenggara	1002410	\N	Jurisdiction	\N
1006259	Bali	Bali	1002410	\N	Jurisdiction	\N
1006260	Maluku	Maluku	1002410	\N	Jurisdiction	\N
1006262	Maluku Utara	Maluku Utara	1002410	\N	Jurisdiction	\N
1006265	Riau Islands	Riau Islands	1002410	\N	Jurisdiction	\N
1006266	Bangka???Belitung Islands	Bangka-Belitung Islands	1002410	\N	Jurisdiction	\N
1006267	South Sumatra	South Sumatra	1002410	\N	Jurisdiction	\N
1006268	Banten	Banten	1002410	\N	Jurisdiction	\N
1006271	West Nusa Tenggara	West Nusa Tenggara	1002410	\N	Jurisdiction	\N
1006272	West Papua	West Papua	1002410	\N	Jurisdiction	\N
1006275	East Kalimantan	East Kalimantan	1002410	\N	Jurisdiction	\N
1006276	Central Sulawesi	Central Sulawesi	1002410	\N	Jurisdiction	\N
1006278	Riau	Riau	1002410	\N	Jurisdiction	\N
1006279	Papua	Papua	1002410	\N	Jurisdiction	\N
1006282	Jakarta Raya	Jakarta Raya	1002410	\N	Jurisdiction	\N
1006283	Gorontalo	Gorontalo	1002410	\N	Jurisdiction	\N
1006284	Bengkulu	Bengkulu	1002410	\N	Jurisdiction	\N
1006285	Leinster	Leinster	1002413	\N	Jurisdiction	\N
1006286	Munster	Munster	1002413	\N	Jurisdiction	\N
1006288	Ulster	Ulster	1002413	\N	Jurisdiction	\N
1006291	Central District	Central District	1002415	\N	Jurisdiction	\N
1006292	Tel Aviv	Tel Aviv	1002415	\N	Jurisdiction	\N
1006293	Haifa	Haifa	1002415	\N	Jurisdiction	\N
1006296	Kashmir	Kashmir	1002409	\N	Jurisdiction	\N
1006297	Tamil Nadu	Tamil Nadu	1002409	\N	Jurisdiction	\N
1006298	Nagaland	Nagaland	1002409	\N	Jurisdiction	\N
1006302	Karnataka	Karnataka	1002409	\N	Jurisdiction	\N
1006304	Haryana	Haryana	1002409	\N	Jurisdiction	\N
1006305	Rajasthan	Rajasthan	1002409	\N	Jurisdiction	\N
1006306	Bihar	Bihar	1002409	\N	Jurisdiction	\N
1006309	Kerala	Kerala	1002409	\N	Jurisdiction	\N
1006310	Goa	Goa	1002409	\N	Jurisdiction	\N
1006311	Uttarakhand	Uttarakhand	1002409	\N	Jurisdiction	\N
1006314	Assam	Assam	1002409	\N	Jurisdiction	\N
1006315	Tripura	Tripura	1002409	\N	Jurisdiction	\N
1006316	Meghalaya	Meghalaya	1002409	\N	Jurisdiction	\N
1006318	Odisha	Odisha	1002409	\N	Jurisdiction	\N
1006320	Punjab	Punjab	1002409	\N	Jurisdiction	\N
1006322	Dadra and Nagar Haveli	Dadra and Nagar Haveli	1002409	\N	Jurisdiction	\N
1006323	Mizoram	Mizoram	1002409	\N	Jurisdiction	\N
1006326	Arunachal Pradesh	Arunachal Pradesh	1002409	\N	Jurisdiction	\N
1006327	NCT	NCT	1002409	\N	Jurisdiction	\N
1006328	Sikkim	Sikkim	1002409	\N	Jurisdiction	\N
1006330	Chandigarh	Chandigarh	1002409	\N	Jurisdiction	\N
1006332	Basra Governorate	Basra Governorate	1002412	\N	Jurisdiction	\N
1006334	N??naw??	Ninawa	1002412	\N	Jurisdiction	\N
1006335	B??bil	Babil	1002412	\N	Jurisdiction	\N
1006337	Anbar	Anbar	1002412	\N	Jurisdiction	\N
1006338	Diy??l??	Diyala	1002412	\N	Jurisdiction	\N
1006340	Karbal????	Karbala??	1002412	\N	Jurisdiction	\N
1006346	Dhi Qar	Dhi Qar	1002412	\N	Jurisdiction	\N
1006349	Hamad??n	Hamadan	1002411	\N	Jurisdiction	\N
1006350	Kerm??nsh??h	Kermanshah	1002411	\N	Jurisdiction	\N
1006352	Semn??n	Semnan	1002411	\N	Jurisdiction	\N
1006353	Tehr??n	Tehran	1002411	\N	Jurisdiction	\N
1006356	Golest??n	Golestan	1002411	\N	Jurisdiction	\N
1006357	Kerman	Kerman	1002411	\N	Jurisdiction	\N
1006358	Yazd	Yazd	1002411	\N	Jurisdiction	\N
1006360	M??zandar??n	Mazandaran	1002411	\N	Jurisdiction	\N
1006362	Qazv??n	Qazvin	1002411	\N	Jurisdiction	\N
1006364	East Azerbaijan	East Azerbaijan	1002411	\N	Jurisdiction	\N
1006365	Khuzestan	Khuzestan	1002411	\N	Jurisdiction	\N
1006367	Fars	Fars	1002411	\N	Jurisdiction	\N
1006369	Isfahan	Isfahan	1002411	\N	Jurisdiction	\N
1006370	Markazi	Markazi	1002411	\N	Jurisdiction	\N
1006371	Kordest??n	Kordestan	1002411	\N	Jurisdiction	\N
1006375	Ardab??l	Ardabil	1002411	\N	Jurisdiction	\N
1006376	Alborz	Alborz	1002411	\N	Jurisdiction	\N
1006377	??l??m	Ilam	1002411	\N	Jurisdiction	\N
1006378	Bushehr	Bushehr	1002411	\N	Jurisdiction	\N
1007215	Cara??-Severin	Caras-Severin	1002490	\N	Jurisdiction	\N
1006381	Capital Region	Capital Region	1002408	\N	Jurisdiction	\N
1006382	Sicily	Sicily	1002416	\N	Jurisdiction	\N
1006384	Sardinia	Sardinia	1002416	\N	Jurisdiction	\N
1006386	Emilia-Romagna	Emilia-Romagna	1002416	\N	Jurisdiction	\N
1006387	Lombardy	Lombardy	1002416	\N	Jurisdiction	\N
1006388	Veneto	Veneto	1002416	\N	Jurisdiction	\N
1006391	Tuscany	Tuscany	1002416	\N	Jurisdiction	\N
1006393	Liguria	Liguria	1002416	\N	Jurisdiction	\N
1006394	Abruzzo	Abruzzo	1002416	\N	Jurisdiction	\N
1006397	The Marches	The Marches	1002416	\N	Jurisdiction	\N
1006398	Umbria	Umbria	1002416	\N	Jurisdiction	\N
1006399	Molise	Molise	1002416	\N	Jurisdiction	\N
1006401	Aosta Valley	Aosta Valley	1002416	\N	Jurisdiction	\N
1006402	St Helier	St Helier	1002420	\N	Jurisdiction	\N
1006405	Saint Andrew	Saint Andrew	1002418	\N	Jurisdiction	\N
1006406	Saint James	Saint James	1002418	\N	Jurisdiction	\N
1006407	Clarendon	Clarendon	1002418	\N	Jurisdiction	\N
1006409	Kingston	Kingston	1002418	\N	Jurisdiction	\N
1006411	Madaba	Madaba	1002421	\N	Jurisdiction	\N
1006412	Ma???an	Ma'an	1002421	\N	Jurisdiction	\N
1006414	Jerash	Jerash	1002421	\N	Jurisdiction	\N
1006417	Tafielah	Tafielah	1002421	\N	Jurisdiction	\N
1006418	Balqa	Balqa	1002421	\N	Jurisdiction	\N
1006420	Mafraq	Mafraq	1002421	\N	Jurisdiction	\N
1006421	Aqaba	Aqaba	1002421	\N	Jurisdiction	\N
1006424	Hy??go	Hyogo	1002419	\N	Jurisdiction	\N
1006425	Yamagata	Yamagata	1002419	\N	Jurisdiction	\N
1006426	Gifu	Gifu	1002419	\N	Jurisdiction	\N
1006429	Saitama	Saitama	1002419	\N	Jurisdiction	\N
1006431	Niigata	Niigata	1002419	\N	Jurisdiction	\N
1006432	Tottori	Tottori	1002419	\N	Jurisdiction	\N
1006433	Mie	Mie	1002419	\N	Jurisdiction	\N
1006436	Kumamoto	Kumamoto	1002419	\N	Jurisdiction	\N
1006437	Toyama	Toyama	1002419	\N	Jurisdiction	\N
1006439	??saka	Osaka	1002419	\N	Jurisdiction	\N
1006442	Tochigi	Tochigi	1002419	\N	Jurisdiction	\N
1006443	Tokushima	Tokushima	1002419	\N	Jurisdiction	\N
1006444	Oita	Oita	1002419	\N	Jurisdiction	\N
1006447	Yamanashi	Yamanashi	1002419	\N	Jurisdiction	\N
1006448	Nagano	Nagano	1002419	\N	Jurisdiction	\N
1006450	Aichi	Aichi	1002419	\N	Jurisdiction	\N
1006452	Fukui	Fukui	1002419	\N	Jurisdiction	\N
1006454	Kagawa	Kagawa	1002419	\N	Jurisdiction	\N
1006455	Okinawa	Okinawa	1002419	\N	Jurisdiction	\N
1006459	Chiba	Chiba	1002419	\N	Jurisdiction	\N
1006461	Hiroshima	Hiroshima	1002419	\N	Jurisdiction	\N
1006462	Kochi	Kochi	1002419	\N	Jurisdiction	\N
1006465	Miyagi	Miyagi	1002419	\N	Jurisdiction	\N
1006466	Iwate	Iwate	1002419	\N	Jurisdiction	\N
1006467	Hokkaido	Hokkaido	1002419	\N	Jurisdiction	\N
1006470	Wajir	Wajir	1002423	\N	Jurisdiction	\N
1006472	Nairobi Area	Nairobi Area	1002423	\N	Jurisdiction	\N
1006473	Nakuru	Nakuru	1002423	\N	Jurisdiction	\N
1006474	Nyeri	Nyeri	1002423	\N	Jurisdiction	\N
1006477	Kakamega	Kakamega	1002423	\N	Jurisdiction	\N
1006478	Kisumu	Kisumu	1002423	\N	Jurisdiction	\N
1006480	Mombasa	Mombasa	1002423	\N	Jurisdiction	\N
1006482	Meru	Meru	1002423	\N	Jurisdiction	\N
1006485	Mandera	Mandera	1002423	\N	Jurisdiction	\N
1006486	Kilifi	Kilifi	1002423	\N	Jurisdiction	\N
1006489	Busia	Busia	1002423	\N	Jurisdiction	\N
1006490	Turkana	Turkana	1002423	\N	Jurisdiction	\N
1006492	Kitui	Kitui	1002423	\N	Jurisdiction	\N
1006495	Kiambu	Kiambu	1002423	\N	Jurisdiction	\N
1006498	Murang'A	Murang'A	1002423	\N	Jurisdiction	\N
1006499	West Pokot	West Pokot	1002423	\N	Jurisdiction	\N
1006502	Homa Bay	Homa Bay	1002423	\N	Jurisdiction	\N
1006503	Garissa	Garissa	1002423	\N	Jurisdiction	\N
1006505	Uasin Gishu	Uasin Gishu	1002423	\N	Jurisdiction	\N
1006508	Batken	Batken	1002427	\N	Jurisdiction	\N
1006509	Ysyk-K??l	Ysyk-Kol	1002427	\N	Jurisdiction	\N
1006510	Ch??y	Chuy	1002427	\N	Jurisdiction	\N
1006513	Osh	Osh	1002427	\N	Jurisdiction	\N
1006514	Naryn	Naryn	1002427	\N	Jurisdiction	\N
1006516	Osh City	Osh City	1002427	\N	Jurisdiction	\N
1006518	Kandal	Kandal	1002347	\N	Jurisdiction	\N
1006520	Svay Rieng	Svay Rieng	1002347	\N	Jurisdiction	\N
1006521	Stung Treng	Stung Treng	1002347	\N	Jurisdiction	\N
1006523	Siem Reap	Siem Reap	1002347	\N	Jurisdiction	\N
1006524	Prey Veng	Prey Veng	1002347	\N	Jurisdiction	\N
1006525	Pursat	Pursat	1002347	\N	Jurisdiction	\N
1006527	Preah Vihear	Preah Vihear	1002347	\N	Jurisdiction	\N
1006528	Pailin	Pailin	1002347	\N	Jurisdiction	\N
1006531	Kratie	Kratie	1002347	\N	Jurisdiction	\N
1006532	Kampot	Kampot	1002347	\N	Jurisdiction	\N
1006533	Kampong Thom	Kampong Thom	1002347	\N	Jurisdiction	\N
1006536	Kampong Chhnang	Kampong Chhnang	1002347	\N	Jurisdiction	\N
1006537	Kampong Cham	Kampong Cham	1002347	\N	Jurisdiction	\N
1006539	Gilbert Islands	Gilbert Islands	1002424	\N	Jurisdiction	\N
1006540	Anjouan	Anjouan	1002359	\N	Jurisdiction	\N
1006543	Hwanghae-namdo	Hwanghae-namdo	1002471	\N	Jurisdiction	\N
1006544	Kangw??n-do	Kangwon-do	1002471	\N	Jurisdiction	\N
1006545	Pyongyang	Pyongyang	1002471	\N	Jurisdiction	\N
1006546	Hwanghae-bukto	Hwanghae-bukto	1002471	\N	Jurisdiction	\N
1006549	P'y??ngan-bukto	P'yongan-bukto	1002471	\N	Jurisdiction	\N
1006550	Rason	Rason	1002471	\N	Jurisdiction	\N
1006552	Yanggang-do	Yanggang-do	1002471	\N	Jurisdiction	\N
1006553	Chagang-do	Chagang-do	1002471	\N	Jurisdiction	\N
1006555	Gangwon-do	Gangwon-do	1002516	\N	Jurisdiction	\N
1006557	Chungcheongbuk-do	Chungcheongbuk-do	1002516	\N	Jurisdiction	\N
1006558	Gyeonggi-do	Gyeonggi-do	1002516	\N	Jurisdiction	\N
1006560	Gyeongsangnam-do	Gyeongsangnam-do	1002516	\N	Jurisdiction	\N
1006561	Jeollabuk-do	Jeollabuk-do	1002516	\N	Jurisdiction	\N
1006562	Ulsan	Ulsan	1002516	\N	Jurisdiction	\N
1006564	Daegu	Daegu	1002516	\N	Jurisdiction	\N
1006566	Busan	Busan	1002516	\N	Jurisdiction	\N
1006567	Gwangju	Gwangju	1002516	\N	Jurisdiction	\N
1006570	Al Farwaniyah	Al Farwaniyah	1002426	\N	Jurisdiction	\N
1006572	Al A???mad??	Al Ahmadi	1002426	\N	Jurisdiction	\N
1006573	Al Asimah	Al Asimah	1002426	\N	Jurisdiction	\N
1006576	George Town	George Town	1002351	\N	Jurisdiction	\N
1006577	Mangghysta??	Mangghystau	1002422	\N	Jurisdiction	\N
1006578	Aqt??be	Aqtobe	1002422	\N	Jurisdiction	\N
1006579	Atyra??	Atyrau	1002422	\N	Jurisdiction	\N
1006582	East Kazakhstan	East Kazakhstan	1002422	\N	Jurisdiction	\N
1006583	Qyzylorda	Qyzylorda	1002422	\N	Jurisdiction	\N
1006584	Qostanay	Qostanay	1002422	\N	Jurisdiction	\N
1006587	Almaty Oblysy	Almaty Oblysy	1002422	\N	Jurisdiction	\N
1006589	Pavlodar	Pavlodar	1002422	\N	Jurisdiction	\N
1006590	Aqmola	Aqmola	1002422	\N	Jurisdiction	\N
1006591	Bayqongyr Qalasy	Bayqongyr Qalasy	1002422	\N	Jurisdiction	\N
1006594	Vientiane	Vientiane	1002428	\N	Jurisdiction	\N
1006595	Houaphan	Houaphan	1002428	\N	Jurisdiction	\N
1006596	Savannahkh??t	Savannahkhet	1002428	\N	Jurisdiction	\N
1006597	Champasak	Champasak	1002428	\N	Jurisdiction	\N
1006600	Xiangkhoang	Xiangkhoang	1002428	\N	Jurisdiction	\N
1006602	Khammouan	Khammouan	1002428	\N	Jurisdiction	\N
1006603	Louangphabang	Louangphabang	1002428	\N	Jurisdiction	\N
1006604	Bokeo Province	Bokeo Province	1002428	\N	Jurisdiction	\N
1006605	B??qaa	Beqaa	1002430	\N	Jurisdiction	\N
1006608	Beyrouth	Beyrouth	1002430	\N	Jurisdiction	\N
1006609	Mont-Liban	Mont-Liban	1002430	\N	Jurisdiction	\N
1006611	Baalbek-Hermel	Baalbek-Hermel	1002430	\N	Jurisdiction	\N
1006613	Vaduz	Vaduz	1002434	\N	Jurisdiction	\N
1006615	Southern	Southern	1002519	\N	Jurisdiction	\N
1006616	Northern Province	Northern Province	1002519	\N	Jurisdiction	\N
1006618	Sabaragamuwa	Sabaragamuwa	1002519	\N	Jurisdiction	\N
1006619	North Western	North Western	1002519	\N	Jurisdiction	\N
1006624	Nimba	Nimba	1002432	\N	Jurisdiction	\N
1006625	Lofa	Lofa	1002432	\N	Jurisdiction	\N
1006626	Montserrado	Montserrado	1002432	\N	Jurisdiction	\N
1006627	Margibi	Margibi	1002432	\N	Jurisdiction	\N
1006630	Bong	Bong	1002432	\N	Jurisdiction	\N
1006632	Quthing	Quthing	1002431	\N	Jurisdiction	\N
1006633	Qacha??s Nek	Qacha??s Nek	1002431	\N	Jurisdiction	\N
1006635	Maseru	Maseru	1002431	\N	Jurisdiction	\N
1006637	Mafeteng	Mafeteng	1002431	\N	Jurisdiction	\N
1006641	Tel??i?? apskritis	Telsiu apskritis	1002435	\N	Jurisdiction	\N
1006642	Taurag??s apskritis	Taurages apskritis	1002435	\N	Jurisdiction	\N
1006644	??iauli?? apskritis	Siauliu apskritis	1002435	\N	Jurisdiction	\N
1006645	Panev????ys	Panevezys	1002435	\N	Jurisdiction	\N
1006647	Kauno apskritis	Kauno apskritis	1002435	\N	Jurisdiction	\N
1007421	Nugaal	Nugaal	1002513	\N	Jurisdiction	\N
1006649	Luxembourg	Luxembourg	1002436	\N	Jurisdiction	\N
1006650	Valmieras Rajons	Valmieras Rajons	1002429	\N	Jurisdiction	\N
1006651	Ventspils	Ventspils	1002429	\N	Jurisdiction	\N
1006654	Salaspils	Salaspils	1002429	\N	Jurisdiction	\N
1006655	Riga	Riga	1002429	\N	Jurisdiction	\N
1006656	R??zekne	Rezekne	1002429	\N	Jurisdiction	\N
1006657	Ogre	Ogre	1002429	\N	Jurisdiction	\N
1006661	Daugavpils municipality	Daugavpils municipality	1002429	\N	Jurisdiction	\N
1006662	C??su Rajons	Cesu Rajons	1002429	\N	Jurisdiction	\N
1006664	Bangh??z??	Banghazi	1002433	\N	Jurisdiction	\N
1006665	Darnah	Darnah	1002433	\N	Jurisdiction	\N
1006667	Al Kufrah	Al Kufrah	1002433	\N	Jurisdiction	\N
1006668	Al Marj	Al Marj	1002433	\N	Jurisdiction	\N
1006669	Al Jabal al Akh???ar	Al Jabal al Akhdar	1002433	\N	Jurisdiction	\N
1006671	Mi??r??tah	Misratah	1002433	\N	Jurisdiction	\N
1006673	Al Jufrah	Al Jufrah	1002433	\N	Jurisdiction	\N
1006674	Al Marqab	Al Marqab	1002433	\N	Jurisdiction	\N
1006675	Tripoli	Tripoli	1002433	\N	Jurisdiction	\N
1006677	Az Z??wiyah	Az Zawiyah	1002433	\N	Jurisdiction	\N
1006678	Sabh??	Sabha	1002433	\N	Jurisdiction	\N
1006680	Murzuq	Murzuq	1002433	\N	Jurisdiction	\N
1006682	Ash Sh????i??	Ash Shati??	1002433	\N	Jurisdiction	\N
1006684	Oriental	Oriental	1002457	\N	Jurisdiction	\N
1006685	Souss-Massa-Dr??a	Souss-Massa-Draa	1002457	\N	Jurisdiction	\N
1006687	Taza-Al Hoceima-Taounate	Taza-Al Hoceima-Taounate	1002457	\N	Jurisdiction	\N
1006689	Tanger-T??touan	Tanger-Tetouan	1002457	\N	Jurisdiction	\N
1006690	Guelmim-Es Smara	Guelmim-Es Smara	1002457	\N	Jurisdiction	\N
1006692	Chaouia-Ouardigha	Chaouia-Ouardigha	1002457	\N	Jurisdiction	\N
1006693	F??s-Boulemane	Fes-Boulemane	1002457	\N	Jurisdiction	\N
1006695	Mekn??s-Tafilalet	Meknes-Tafilalet	1002457	\N	Jurisdiction	\N
1006696	Marrakech-Tensift-Al Haouz	Marrakech-Tensift-Al Haouz	1002457	\N	Jurisdiction	\N
1006697	Tadla-Azilal	Tadla-Azilal	1002457	\N	Jurisdiction	\N
1006699	Raionul Edine??	Raionul Edinet	1002452	\N	Jurisdiction	\N
1006702	Str????eni	Straseni	1002452	\N	Jurisdiction	\N
1006703	S??ngerei	Singerei	1002452	\N	Jurisdiction	\N
1006705	Orhei	Orhei	1002452	\N	Jurisdiction	\N
1006706	H??nce??ti	Hincesti	1002452	\N	Jurisdiction	\N
1006707	C??u??eni	Causeni	1002452	\N	Jurisdiction	\N
1006710	Drochia	Drochia	1002452	\N	Jurisdiction	\N
1006711	G??g??uzia	Gagauzia	1002452	\N	Jurisdiction	\N
1006713	Cahul	Cahul	1002452	\N	Jurisdiction	\N
1006714	Bender	Bender	1002452	\N	Jurisdiction	\N
1006717	Pljevlja	Pljevlja	1002455	\N	Jurisdiction	\N
1006718	Op??tina Nik??i??	Opstina Niksic	1002455	\N	Jurisdiction	\N
1006719	Herceg Novi	Herceg Novi	1002455	\N	Jurisdiction	\N
1006721	Budva	Budva	1002455	\N	Jurisdiction	\N
1006723	Bar	Bar	1002455	\N	Jurisdiction	\N
1006725	Atsimo-Atsinanana	Atsimo-Atsinanana	1002439	\N	Jurisdiction	\N
1006726	Analanjirofo	Analanjirofo	1002439	\N	Jurisdiction	\N
1006728	Androy	Androy	1002439	\N	Jurisdiction	\N
1006731	Anosy	Anosy	1002439	\N	Jurisdiction	\N
1006732	Itasy	Itasy	1002439	\N	Jurisdiction	\N
1006734	Boeny	Boeny	1002439	\N	Jurisdiction	\N
1006735	Sava	Sava	1002439	\N	Jurisdiction	\N
1006737	Analamanga	Analamanga	1002439	\N	Jurisdiction	\N
1006738	Menabe	Menabe	1002439	\N	Jurisdiction	\N
1006741	Upper Matsiatra	Upper Matsiatra	1002439	\N	Jurisdiction	\N
1006742	Ihorombe	Ihorombe	1002439	\N	Jurisdiction	\N
1006744	Sofia	Sofia	1002439	\N	Jurisdiction	\N
1006953	Kwara	Kwara	1002468	\N	Jurisdiction	\N
1006746	Majuro Atoll	Majuro Atoll	1002445	\N	Jurisdiction	\N
1006747	??elino	Zelino	1002438	\N	Jurisdiction	\N
1006750	Tetovo	Tetovo	1002438	\N	Jurisdiction	\N
1006751	Tearce	Tearce	1002438	\N	Jurisdiction	\N
1006753	Strumica	Strumica	1002438	\N	Jurisdiction	\N
1006755	??tip	Stip	1002438	\N	Jurisdiction	\N
1006757	Saraj	Saraj	1002438	\N	Jurisdiction	\N
1006758	Resen	Resen	1002438	\N	Jurisdiction	\N
1006760	Prilep	Prilep	1002438	\N	Jurisdiction	\N
1006762	Vrap??i??te	Vrapciste	1002438	\N	Jurisdiction	\N
1006764	Opstina Lipkovo	Opstina Lipkovo	1002438	\N	Jurisdiction	\N
1006767	Ko??ani	Kocani	1002438	\N	Jurisdiction	\N
1006768	Ki??evo	Kicevo	1002438	\N	Jurisdiction	\N
1006769	Kavadarci	Kavadarci	1002438	\N	Jurisdiction	\N
1006770	Bogovinje	Bogovinje	1002438	\N	Jurisdiction	\N
1006773	Del??evo	Delcevo	1002438	\N	Jurisdiction	\N
1006774	Debar	Debar	1002438	\N	Jurisdiction	\N
1006777	??uto Orizari	Suto Orizari	1002438	\N	Jurisdiction	\N
1006778	Butel	Butel	1002438	\N	Jurisdiction	\N
1006781	Kisela Voda	Kisela Voda	1002438	\N	Jurisdiction	\N
1006783	Sikasso	Sikasso	1002443	\N	Jurisdiction	\N
1006784	Tombouctou	Tombouctou	1002443	\N	Jurisdiction	\N
1006785	S??gou	Segou	1002443	\N	Jurisdiction	\N
1006788	Koulikoro	Koulikoro	1002443	\N	Jurisdiction	\N
1006789	Gao	Gao	1002443	\N	Jurisdiction	\N
1006791	Magway	Magway	1002459	\N	Jurisdiction	\N
1006794	Yangon	Yangon	1002459	\N	Jurisdiction	\N
1006795	Bago	Bago	1002459	\N	Jurisdiction	\N
1006796	Mon	Mon	1002459	\N	Jurisdiction	\N
1006799	Rakhine	Rakhine	1002459	\N	Jurisdiction	\N
1006800	Sagain	Sagain	1002459	\N	Jurisdiction	\N
1006802	Kachin	Kachin	1002459	\N	Jurisdiction	\N
1006803	Kayah	Kayah	1002459	\N	Jurisdiction	\N
1006806	Uvs	Uvs	1002454	\N	Jurisdiction	\N
1006808	Hovd	Hovd	1002454	\N	Jurisdiction	\N
1006809	Gov??-Altay	Govi-Altay	1002454	\N	Jurisdiction	\N
1006811	Selenge	Selenge	1002454	\N	Jurisdiction	\N
1006813	Middle Gov??	Middle Govi	1002454	\N	Jurisdiction	\N
1006814	??v??rhangay	Ovorhangay	1002454	\N	Jurisdiction	\N
1006815	Orhon	Orhon	1002454	\N	Jurisdiction	\N
1006818	East Gobi Aymag	East Gobi Aymag	1002454	\N	Jurisdiction	\N
1006820	Bayanhongor	Bayanhongor	1002454	\N	Jurisdiction	\N
1006821	S??hbaatar	Suhbaatar	1002454	\N	Jurisdiction	\N
1006824	Saipan	Saipan	1002472	\N	Jurisdiction	\N
1006825	Martinique	Martinique	1002446	\N	Jurisdiction	\N
1006827	Trarza	Trarza	1002447	\N	Jurisdiction	\N
1006829	Nouakchott	Nouakchott	1002447	\N	Jurisdiction	\N
1006831	Hodh ech Chargui	Hodh ech Chargui	1002447	\N	Jurisdiction	\N
1006832	Assaba	Assaba	1002447	\N	Jurisdiction	\N
1006833	Gorgol	Gorgol	1002447	\N	Jurisdiction	\N
1006835	Brakna	Brakna	1002447	\N	Jurisdiction	\N
1006837	Saint Peter	Saint Peter	1002456	\N	Jurisdiction	\N
1006838	??a??-??abbar	Haz-Zabbar	1002444	\N	Jurisdiction	\N
1006841	Il-Mosta	Il-Mosta	1002444	\N	Jurisdiction	\N
1006842	Birkirkara	Birkirkara	1002444	\N	Jurisdiction	\N
1006843	Plaines Wilhems	Plaines Wilhems	1002448	\N	Jurisdiction	\N
1006845	Moka	Moka	1002448	\N	Jurisdiction	\N
1006847	Grand Port	Grand Port	1002448	\N	Jurisdiction	\N
1006849	Flacq	Flacq	1002448	\N	Jurisdiction	\N
1006850	Kaafu Atoll	Kaafu Atoll	1002442	\N	Jurisdiction	\N
1006852	Southern Region	Southern Region	1002440	\N	Jurisdiction	\N
1006854	Tamaulipas	Tamaulipas	1002450	\N	Jurisdiction	\N
1006855	M??xico	Mexico	1002450	\N	Jurisdiction	\N
1006856	Guerrero	Guerrero	1002450	\N	Jurisdiction	\N
1006859	Morelos	Morelos	1002450	\N	Jurisdiction	\N
1006860	Mexico City	Mexico City	1002450	\N	Jurisdiction	\N
1006862	Tabasco	Tabasco	1002450	\N	Jurisdiction	\N
1006865	Quer??taro	Queretaro	1002450	\N	Jurisdiction	\N
1006866	San Luis Potos??	San Luis Potosi	1002450	\N	Jurisdiction	\N
1006867	Oaxaca	Oaxaca	1002450	\N	Jurisdiction	\N
1006870	Nuevo Le??n	Nuevo Leon	1002450	\N	Jurisdiction	\N
1006871	Campeche	Campeche	1002450	\N	Jurisdiction	\N
1006873	Sinaloa	Sinaloa	1002450	\N	Jurisdiction	\N
1006874	Jalisco	Jalisco	1002450	\N	Jurisdiction	\N
1006877	Zacatecas	Zacatecas	1002450	\N	Jurisdiction	\N
1006878	Guanajuato	Guanajuato	1002450	\N	Jurisdiction	\N
1006879	Coahuila	Coahuila	1002450	\N	Jurisdiction	\N
1006881	Nayarit	Nayarit	1002450	\N	Jurisdiction	\N
1006884	Aguascalientes	Aguascalientes	1002450	\N	Jurisdiction	\N
1006886	Kedah	Kedah	1002441	\N	Jurisdiction	\N
1006888	Johor	Johor	1002441	\N	Jurisdiction	\N
1006891	Sabah	Sabah	1002441	\N	Jurisdiction	\N
1006892	Labuan	Labuan	1002441	\N	Jurisdiction	\N
1006893	Perak	Perak	1002441	\N	Jurisdiction	\N
1006896	Melaka	Melaka	1002441	\N	Jurisdiction	\N
1006897	Penang	Penang	1002441	\N	Jurisdiction	\N
1006899	Sarawak	Sarawak	1002441	\N	Jurisdiction	\N
1006900	Perlis	Perlis	1002441	\N	Jurisdiction	\N
1006902	Gaza	Gaza	1002458	\N	Jurisdiction	\N
1006904	Tete	Tete	1002458	\N	Jurisdiction	\N
1006905	Maputo	Maputo	1002458	\N	Jurisdiction	\N
1006908	Nampula	Nampula	1002458	\N	Jurisdiction	\N
1006910	Maputo City	Maputo City	1002458	\N	Jurisdiction	\N
1006911	Niassa	Niassa	1002458	\N	Jurisdiction	\N
1006912	Manica	Manica	1002458	\N	Jurisdiction	\N
1006914	Khomas	Khomas	1002460	\N	Jurisdiction	\N
1006917	Hardap	Hardap	1002460	\N	Jurisdiction	\N
1006918	Otjozondjupa	Otjozondjupa	1002460	\N	Jurisdiction	\N
1006919	Oshana	Oshana	1002460	\N	Jurisdiction	\N
1006922	South Province	South Province	1002464	\N	Jurisdiction	\N
1006923	Tahoua	Tahoua	1002467	\N	Jurisdiction	\N
1006925	Tillab??ri	Tillaberi	1002467	\N	Jurisdiction	\N
1006926	Maradi	Maradi	1002467	\N	Jurisdiction	\N
1006930	Agadez	Agadez	1002467	\N	Jurisdiction	\N
1006933	Kaduna	Kaduna	1002468	\N	Jurisdiction	\N
1006935	Bayelsa	Bayelsa	1002468	\N	Jurisdiction	\N
1006936	Taraba	Taraba	1002468	\N	Jurisdiction	\N
1006939	Nassarawa	Nassarawa	1002468	\N	Jurisdiction	\N
1006940	Akwa Ibom	Akwa Ibom	1002468	\N	Jurisdiction	\N
1006943	Cross River	Cross River	1002468	\N	Jurisdiction	\N
1006946	Zamfara	Zamfara	1002468	\N	Jurisdiction	\N
1006949	Ogun	Ogun	1002468	\N	Jurisdiction	\N
1006950	Yobe	Yobe	1002468	\N	Jurisdiction	\N
1006955	Osun	Osun	1002468	\N	Jurisdiction	\N
1006956	Ondo	Ondo	1002468	\N	Jurisdiction	\N
1006957	Imo	Imo	1002468	\N	Jurisdiction	\N
1006960	Enugu	Enugu	1002468	\N	Jurisdiction	\N
1006962	Katsina	Katsina	1002468	\N	Jurisdiction	\N
1006963	Lagos	Lagos	1002468	\N	Jurisdiction	\N
1006966	Bauchi	Bauchi	1002468	\N	Jurisdiction	\N
1006967	Ebonyi	Ebonyi	1002468	\N	Jurisdiction	\N
1006968	Managua	Managua	1002466	\N	Jurisdiction	\N
1006971	Atl??ntico Norte (RAAN)	Atlantico Norte (RAAN)	1002466	\N	Jurisdiction	\N
1006972	Carazo	Carazo	1002466	\N	Jurisdiction	\N
1006973	Rivas	Rivas	1002466	\N	Jurisdiction	\N
1006976	Nueva Segovia	Nueva Segovia	1002466	\N	Jurisdiction	\N
1006977	Granada	Granada	1002466	\N	Jurisdiction	\N
1006979	Masaya	Masaya	1002466	\N	Jurisdiction	\N
1006980	Chontales	Chontales	1002466	\N	Jurisdiction	\N
1006983	Boaco	Boaco	1002466	\N	Jurisdiction	\N
1006984	Overijssel	Overijssel	1002463	\N	Jurisdiction	\N
1006986	Gelderland	Gelderland	1002463	\N	Jurisdiction	\N
1006988	Utrecht	Utrecht	1002463	\N	Jurisdiction	\N
1006990	North Holland	North Holland	1002463	\N	Jurisdiction	\N
1006991	Friesland	Friesland	1002463	\N	Jurisdiction	\N
1006992	Groningen	Groningen	1002463	\N	Jurisdiction	\N
1006995	Drenthe	Drenthe	1002463	\N	Jurisdiction	\N
1006997	Troms	Troms	1002473	\N	Jurisdiction	\N
1006998	Vestfold	Vestfold	1002473	\N	Jurisdiction	\N
1007001	Telemark	Telemark	1002473	\N	Jurisdiction	\N
1007002	??stfold	Ostfold	1002473	\N	Jurisdiction	\N
1007003	Oslo	Oslo	1002473	\N	Jurisdiction	\N
1007005	Nordland	Nordland	1002473	\N	Jurisdiction	\N
1007007	Vest-Agder	Vest-Agder	1002473	\N	Jurisdiction	\N
1007008	Buskerud	Buskerud	1002473	\N	Jurisdiction	\N
1007010	Hordaland	Hordaland	1002473	\N	Jurisdiction	\N
1007013	Mid Western	Mid Western	1002462	\N	Jurisdiction	\N
1007014	Far Western	Far Western	1002462	\N	Jurisdiction	\N
1007015	Eastern Region	Eastern Region	1002462	\N	Jurisdiction	\N
1007017	Yaren	Yaren	1002461	\N	Jurisdiction	\N
1007019	Manawatu-Wanganui	Manawatu-Wanganui	1002465	\N	Jurisdiction	\N
1007020	Canterbury	Canterbury	1002465	\N	Jurisdiction	\N
1007022	Auckland	Auckland	1002465	\N	Jurisdiction	\N
1007025	Hawke's Bay	Hawke's Bay	1002465	\N	Jurisdiction	\N
1007028	Gisborne	Gisborne	1002465	\N	Jurisdiction	\N
1007030	Northland	Northland	1002465	\N	Jurisdiction	\N
1007031	Marlborough	Marlborough	1002465	\N	Jurisdiction	\N
1007034	Mu?????faz??at ad D??khil??yah	Muhafaz??at ad Dakhiliyah	1002474	\N	Jurisdiction	\N
1007035	Z??uf??r	Z??ufar	1002474	\N	Jurisdiction	\N
1007036	Mu?????faz??at Masqa??	Muhafaz??at Masqat	1002474	\N	Jurisdiction	\N
1007037	Musandam	Musandam	1002474	\N	Jurisdiction	\N
1007040	Al Batinah South Governorate	Al Batinah South Governorate	1002474	\N	Jurisdiction	\N
1007041	Al Buraimi	Al Buraimi	1002474	\N	Jurisdiction	\N
1007044	Chiriqu??	Chiriqui	1002478	\N	Jurisdiction	\N
1007045	Col??n	Colon	1002478	\N	Jurisdiction	\N
1007046	Herrera	Herrera	1002478	\N	Jurisdiction	\N
1007048	Cocl??	Cocle	1002478	\N	Jurisdiction	\N
1007049	Loreto	Loreto	1002481	\N	Jurisdiction	\N
1007052	Tumbes	Tumbes	1002481	\N	Jurisdiction	\N
1007053	Huanuco	Huanuco	1002481	\N	Jurisdiction	\N
1007054	Piura	Piura	1002481	\N	Jurisdiction	\N
1007056	Ucayali	Ucayali	1002481	\N	Jurisdiction	\N
1007059	Ancash	Ancash	1002481	\N	Jurisdiction	\N
1007060	Puno	Puno	1002481	\N	Jurisdiction	\N
1007061	Jun??n	Junin	1002481	\N	Jurisdiction	\N
1007839	Jizzax	Jizzax	1002546	\N	Jurisdiction	\N
1007064	Lima region	Lima region	1002481	\N	Jurisdiction	\N
1007065	Cusco	Cusco	1002481	\N	Jurisdiction	\N
1007066	Ica	Ica	1002481	\N	Jurisdiction	\N
1007069	Lima Province	Lima Province	1002481	\N	Jurisdiction	\N
1007071	Huancavelica	Huancavelica	1002481	\N	Jurisdiction	\N
1007072	Pasco	Pasco	1002481	\N	Jurisdiction	\N
1007073	Callao	Callao	1002481	\N	Jurisdiction	\N
1007076	East Sepik	East Sepik	1002479	\N	Jurisdiction	\N
1007078	Northern Province	Northern Province	1002479	\N	Jurisdiction	\N
1007665	Tokat	Tokat	1002535	\N	Jurisdiction	\N
1007081	Madang	Madang	1002479	\N	Jurisdiction	\N
1007082	Morobe	Morobe	1002479	\N	Jurisdiction	\N
1007085	Eastern Highlands	Eastern Highlands	1002479	\N	Jurisdiction	\N
1007087	Bougainville	Bougainville	1002479	\N	Jurisdiction	\N
1007088	Zamboanga Peninsula	Zamboanga Peninsula	1002482	\N	Jurisdiction	\N
1007090	Bicol	Bicol	1002482	\N	Jurisdiction	\N
1007091	Ilocos	Ilocos	1002482	\N	Jurisdiction	\N
1007093	Calabarzon	Calabarzon	1002482	\N	Jurisdiction	\N
1007094	Caraga	Caraga	1002482	\N	Jurisdiction	\N
1007096	Davao	Davao	1002482	\N	Jurisdiction	\N
1007097	Cagayan Valley	Cagayan Valley	1002482	\N	Jurisdiction	\N
1007099	Central Luzon	Central Luzon	1002482	\N	Jurisdiction	\N
1007100	Metro Manila	Metro Manila	1002482	\N	Jurisdiction	\N
1007101	Eastern Visayas	Eastern Visayas	1002482	\N	Jurisdiction	\N
1007103	Cordillera	Cordillera	1002482	\N	Jurisdiction	\N
1007105	Sindh	Sindh	1002475	\N	Jurisdiction	\N
1007107	Balochist??n	Balochistan	1002475	\N	Jurisdiction	\N
1007109	Punjab	Punjab	1002475	\N	Jurisdiction	\N
1007110	Isl??m??b??d	Islamabad	1002475	\N	Jurisdiction	\N
1007112	Lublin Voivodeship	Lublin Voivodeship	1002484	\N	Jurisdiction	\N
1007113	Podlasie	Podlasie	1002484	\N	Jurisdiction	\N
1007115	????d?? Voivodeship	Lodz Voivodeship	1002484	\N	Jurisdiction	\N
1007117	Warmian-Masurian Voivodeship	Warmian-Masurian Voivodeship	1002484	\N	Jurisdiction	\N
1007118	??wi??tokrzyskie	Swietokrzyskie	1002484	\N	Jurisdiction	\N
1007119	Silesian Voivodeship	Silesian Voivodeship	1002484	\N	Jurisdiction	\N
1007121	Lower Silesian Voivodeship	Lower Silesian Voivodeship	1002484	\N	Jurisdiction	\N
1007122	Lubusz	Lubusz	1002484	\N	Jurisdiction	\N
1007124	Pomeranian Voivodeship	Pomeranian Voivodeship	1002484	\N	Jurisdiction	\N
1007126	Opole Voivodeship	Opole Voivodeship	1002484	\N	Jurisdiction	\N
1007127	Saint-Pierre	Saint-Pierre	1002498	\N	Jurisdiction	\N
1007128	Aguadilla	Aguadilla	1002486	\N	Jurisdiction	\N
1007129	Arecibo	Arecibo	1002486	\N	Jurisdiction	\N
1007131	Bayam??n	Bayamon	1002486	\N	Jurisdiction	\N
1007133	Toa Baja	Toa Baja	1002486	\N	Jurisdiction	\N
1007134	Carolina	Carolina	1002486	\N	Jurisdiction	\N
1007135	Catano	Catano	1002486	\N	Jurisdiction	\N
1007138	Guayama	Guayama	1002486	\N	Jurisdiction	\N
1007140	Humacao	Humacao	1002486	\N	Jurisdiction	\N
1007141	Manati	Manati	1002486	\N	Jurisdiction	\N
1007144	San Juan	San Juan	1002486	\N	Jurisdiction	\N
1007145	Trujillo Alto	Trujillo Alto	1002486	\N	Jurisdiction	\N
1007147	Yauco	Yauco	1002486	\N	Jurisdiction	\N
1007148	Gaza Strip	Gaza Strip	1002477	\N	Jurisdiction	\N
1007151	Santar??m	Santarem	1002485	\N	Jurisdiction	\N
1007153	Faro	Faro	1002485	\N	Jurisdiction	\N
1007154	Portalegre	Portalegre	1002485	\N	Jurisdiction	\N
1007156	Madeira	Madeira	1002485	\N	Jurisdiction	\N
1007159	Beja	Beja	1002485	\N	Jurisdiction	\N
1007160	Viseu	Viseu	1002485	\N	Jurisdiction	\N
1007162	Porto	Porto	1002485	\N	Jurisdiction	\N
1007164	Guarda	Guarda	1002485	\N	Jurisdiction	\N
1007165	Aveiro	Aveiro	1002485	\N	Jurisdiction	\N
1007166	Braga	Braga	1002485	\N	Jurisdiction	\N
1007169	Azores	Azores	1002485	\N	Jurisdiction	\N
1007171	Guair??	Guaira	1002480	\N	Jurisdiction	\N
1007172	Presidente Hayes	Presidente Hayes	1002480	\N	Jurisdiction	\N
1007173	Central	Central	1002480	\N	Jurisdiction	\N
1007176	??eembuc??	Neembucu	1002480	\N	Jurisdiction	\N
1007177	Amambay	Amambay	1002480	\N	Jurisdiction	\N
1007179	Caaguaz??	Caaguazu	1002480	\N	Jurisdiction	\N
1007180	Concepci??n	Concepcion	1002480	\N	Jurisdiction	\N
1007183	Asunci??n	Asuncion	1002480	\N	Jurisdiction	\N
1007185	Balad??yat ar Rayy??n	Baladiyat ar Rayyan	1002487	\N	Jurisdiction	\N
1007186	Al Wakrah	Al Wakrah	1002487	\N	Jurisdiction	\N
1006214	Primorsko-Goranska	Primorsko-Goranska	1002362	\N	Jurisdiction	\N
1006217	Koprivni??ko-Kri??eva??ka	Koprivnicko-Krizevacka	1002362	\N	Jurisdiction	\N
1006225	Nord-Ouest	Nord-Ouest	1002404	\N	Jurisdiction	\N
1006229	Centre	Centre	1002404	\N	Jurisdiction	\N
1006236	Szabolcs-Szatm??r-Bereg	Szabolcs-Szatmar-Bereg	1002407	\N	Jurisdiction	\N
1006241	Kom??rom-Esztergom	Komarom-Esztergom	1002407	\N	Jurisdiction	\N
1006245	Gy??r-Moson-Sopron	Gyor-Moson-Sopron	1002407	\N	Jurisdiction	\N
1006251	North Sumatra	North Sumatra	1002410	\N	Jurisdiction	\N
1006261	North Sulawesi	North Sulawesi	1002410	\N	Jurisdiction	\N
1006264	North Kalimantan	North Kalimantan	1002410	\N	Jurisdiction	\N
1006269	West Kalimantan	West Kalimantan	1002410	\N	Jurisdiction	\N
1006273	West Sumatra	West Sumatra	1002410	\N	Jurisdiction	\N
1006277	Sulawesi Barat	Sulawesi Barat	1002410	\N	Jurisdiction	\N
1006287	Connaught	Connaught	1002413	\N	Jurisdiction	\N
1006290	Northern District	Northern District	1002415	\N	Jurisdiction	\N
1006294	Southern District	Southern District	1002415	\N	Jurisdiction	\N
1006565	Seoul	Seoul	1002516	\N	Jurisdiction	\N
1007219	Harghita	Harghita	1002490	\N	Jurisdiction	\N
1007559	Nan	Nan	1002530	\N	Jurisdiction	\N
1005875	Obock	Obock	1002369	\N	Jurisdiction	\N
1007260	Smolensk	Smolensk	1002491	\N	Jurisdiction	\N
1007261	Jaroslavl	Jaroslavl	1002491	\N	Jurisdiction	\N
1007264	Arkhangelskaya	Arkhangelskaya	1002491	\N	Jurisdiction	\N
1007265	Adygeya	Adygeya	1002491	\N	Jurisdiction	\N
1007266	Leningrad	Leningrad	1002491	\N	Jurisdiction	\N
1007269	Vologda	Vologda	1002491	\N	Jurisdiction	\N
1007270	Kostroma	Kostroma	1002491	\N	Jurisdiction	\N
1007272	Ivanovo	Ivanovo	1002491	\N	Jurisdiction	\N
1007273	Perm	Perm	1002491	\N	Jurisdiction	\N
1007276	Novgorod	Novgorod	1002491	\N	Jurisdiction	\N
1007277	Chechnya	Chechnya	1002491	\N	Jurisdiction	\N
1007278	Ulyanovsk	Ulyanovsk	1002491	\N	Jurisdiction	\N
1007281	Kaliningrad	Kaliningrad	1002491	\N	Jurisdiction	\N
1007282	Kaluga	Kaluga	1002491	\N	Jurisdiction	\N
1007284	Chuvashia	Chuvashia	1002491	\N	Jurisdiction	\N
1007285	Sverdlovsk	Sverdlovsk	1002491	\N	Jurisdiction	\N
1007287	Orjol	Orjol	1002491	\N	Jurisdiction	\N
1007289	Dagestan	Dagestan	1002491	\N	Jurisdiction	\N
1007290	Astrakhan	Astrakhan	1002491	\N	Jurisdiction	\N
1007292	Tjumen	Tjumen	1002491	\N	Jurisdiction	\N
1007294	Kemerovo	Kemerovo	1002491	\N	Jurisdiction	\N
1007297	Tomsk	Tomsk	1002491	\N	Jurisdiction	\N
1007298	Novosibirsk	Novosibirsk	1002491	\N	Jurisdiction	\N
1007300	Yamalo-Nenetskiy Avtonomnyy Okrug	Yamalo-Nenetskiy Avtonomnyy Okrug	1002491	\N	Jurisdiction	\N
1007301	Omsk	Omsk	1002491	\N	Jurisdiction	\N
1007302	Kurgan	Kurgan	1002491	\N	Jurisdiction	\N
1007304	Altai Republic	Altai Republic	1002491	\N	Jurisdiction	\N
1007306	Amur	Amur	1002491	\N	Jurisdiction	\N
1007307	Sakha	Sakha	1002491	\N	Jurisdiction	\N
1007309	Primorskiy	Primorskiy	1002491	\N	Jurisdiction	\N
1007312	Jewish Autonomous Oblast	Jewish Autonomous Oblast	1002491	\N	Jurisdiction	\N
1007313	Kamtsjatka	Kamtsjatka	1002491	\N	Jurisdiction	\N
1007314	Sakhalin	Sakhalin	1002491	\N	Jurisdiction	\N
1007315	Magadan	Magadan	1002491	\N	Jurisdiction	\N
1007318	Southern Province	Southern Province	1002492	\N	Jurisdiction	\N
1007319	Kigali	Kigali	1002492	\N	Jurisdiction	\N
1007320	Western Province	Western Province	1002492	\N	Jurisdiction	\N
1007322	Min??aqat Tab??k	Mintaqat Tabuk	1002503	\N	Jurisdiction	\N
1007324	Makkah	Makkah	1002503	\N	Jurisdiction	\N
1007325	Eastern Province	Eastern Province	1002503	\N	Jurisdiction	\N
1007326	Al Jawf	Al Jawf	1002503	\N	Jurisdiction	\N
1007327	Jizan	Jizan	1002503	\N	Jurisdiction	\N
1007329	Najr??n	Najran	1002503	\N	Jurisdiction	\N
1007331	Al-Qassim	Al-Qassim	1002503	\N	Jurisdiction	\N
1007333	Min??aqat al B?????ah	Mintaqat al Bahah	1002503	\N	Jurisdiction	\N
1007334	Guadalcanal	Guadalcanal	1002512	\N	Jurisdiction	\N
1007337	Al Jaz??rah	Al Jazirah	1002520	\N	Jurisdiction	\N
1007338	Sham??l Kurduf??n	Shamal Kurdufan	1002520	\N	Jurisdiction	\N
1007339	Khartoum	Khartoum	1002520	\N	Jurisdiction	\N
1007340	Red Sea	Red Sea	1002520	\N	Jurisdiction	\N
1007342	Sinn??r	Sinnar	1002520	\N	Jurisdiction	\N
1007345	Kassala	Kassala	1002520	\N	Jurisdiction	\N
1007346	Southern Kordofan	Southern Kordofan	1002520	\N	Jurisdiction	\N
1007347	Al Qa?????rif	Al Qadarif	1002520	\N	Jurisdiction	\N
1007350	Western Darfur	Western Darfur	1002520	\N	Jurisdiction	\N
1007351	Northern Darfur	Northern Darfur	1002520	\N	Jurisdiction	\N
1007353	V??sterbotten	Vasterbotten	1002524	\N	Jurisdiction	\N
1007354	Norrbotten	Norrbotten	1002524	\N	Jurisdiction	\N
1007355	Sk??ne	Skane	1002524	\N	Jurisdiction	\N
1007358	Kalmar	Kalmar	1002524	\N	Jurisdiction	\N
1007359	V??stmanland	Vastmanland	1002524	\N	Jurisdiction	\N
1007361	Halland	Halland	1002524	\N	Jurisdiction	\N
1007363	Stockholm	Stockholm	1002524	\N	Jurisdiction	\N
1007365	V??sternorrland	Vasternorrland	1002524	\N	Jurisdiction	\N
1007366	G??vleborg	Gavleborg	1002524	\N	Jurisdiction	\N
1007368	??rebro	Orebro	1002524	\N	Jurisdiction	\N
1007370	??sterg??tland	Ostergotland	1002524	\N	Jurisdiction	\N
1007372	Blekinge	Blekinge	1002524	\N	Jurisdiction	\N
1007373	Dalarna	Dalarna	1002524	\N	Jurisdiction	\N
1007375	Saint Helena	Saint Helena	1002494	\N	Jurisdiction	\N
1007377	Velenje	Velenje	1002511	\N	Jurisdiction	\N
1007378	Ptuj	Ptuj	1002511	\N	Jurisdiction	\N
1007380	Maribor	Maribor	1002511	\N	Jurisdiction	\N
1007381	Ljubljana	Ljubljana	1002511	\N	Jurisdiction	\N
1007384	Celje	Celje	1002511	\N	Jurisdiction	\N
1007385	Svalbard	Svalbard	1002522	\N	Jurisdiction	\N
1007386	Pre??ovsk??	Presovsky	1002510	\N	Jurisdiction	\N
1007389	Nitriansky	Nitriansky	1002510	\N	Jurisdiction	\N
1007390	??ilinsk??	Zilinsky	1002510	\N	Jurisdiction	\N
1007394	Western Area	Western Area	1002507	\N	Jurisdiction	\N
1007395	Eastern Province	Eastern Province	1002507	\N	Jurisdiction	\N
1007397	Southern Province	Southern Province	1002507	\N	Jurisdiction	\N
1007398	San Marino	San Marino	1002501	\N	Jurisdiction	\N
1007402	Thi??s	Thies	1002504	\N	Jurisdiction	\N
1007403	Tambacounda	Tambacounda	1002504	\N	Jurisdiction	\N
1007404	S??dhiou	Sedhiou	1002504	\N	Jurisdiction	\N
1007406	Fatick	Fatick	1002504	\N	Jurisdiction	\N
1007408	Kaolack	Kaolack	1002504	\N	Jurisdiction	\N
1007410	Matam	Matam	1002504	\N	Jurisdiction	\N
1007411	K??dougou	Kedougou	1002504	\N	Jurisdiction	\N
1007414	Bari	Bari	1002513	\N	Jurisdiction	\N
1007415	Banaadir	Banaadir	1002513	\N	Jurisdiction	\N
1007417	Lower Juba	Lower Juba	1002513	\N	Jurisdiction	\N
1007418	Middle Juba	Middle Juba	1002513	\N	Jurisdiction	\N
1007422	Mudug	Mudug	1002513	\N	Jurisdiction	\N
1007425	Bay	Bay	1002513	\N	Jurisdiction	\N
1007427	Togdheer	Togdheer	1002513	\N	Jurisdiction	\N
1007428	Sool	Sool	1002513	\N	Jurisdiction	\N
1007431	Wanica	Wanica	1002521	\N	Jurisdiction	\N
1007433	Western Equatoria	Western Equatoria	1002517	\N	Jurisdiction	\N
1007435	Northern Bahr al Ghazal	Northern Bahr al Ghazal	1002517	\N	Jurisdiction	\N
1007436	Eastern Equatoria	Eastern Equatoria	1002517	\N	Jurisdiction	\N
1007437	Warrap	Warrap	1002517	\N	Jurisdiction	\N
1007439	Upper Nile	Upper Nile	1002517	\N	Jurisdiction	\N
1007440	Jonglei	Jonglei	1002517	\N	Jurisdiction	\N
1007442	La Paz	La Paz	1002375	\N	Jurisdiction	\N
1007444	San Salvador	San Salvador	1002375	\N	Jurisdiction	\N
1007445	Sonsonate	Sonsonate	1002375	\N	Jurisdiction	\N
1007447	San Vicente	San Vicente	1002375	\N	Jurisdiction	\N
1007450	Cuscatl??n	Cuscatlan	1002375	\N	Jurisdiction	\N
1007451	Moraz??n	Morazan	1002375	\N	Jurisdiction	\N
1007452	La Libertad	La Libertad	1002375	\N	Jurisdiction	\N
1007454	Chalatenango	Chalatenango	1002375	\N	Jurisdiction	\N
1007456	Rif-dimashq	Rif-dimashq	1002526	\N	Jurisdiction	\N
1007458	Tartus	Tartus	1002526	\N	Jurisdiction	\N
1007459	Aleppo	Aleppo	1002526	\N	Jurisdiction	\N
1007460	Homs	Homs	1002526	\N	Jurisdiction	\N
1007463	Idlib	Idlib	1002526	\N	Jurisdiction	\N
1007465	Dimashq	Dimashq	1002526	\N	Jurisdiction	\N
1007466	Al-Hasakah	Al-Hasakah	1002526	\N	Jurisdiction	\N
1007469	Quneitra	Quneitra	1002526	\N	Jurisdiction	\N
1007470	Hhohho	Hhohho	1002523	\N	Jurisdiction	\N
1007472	Ennedi-Ouest	Ennedi-Ouest	1002353	\N	Jurisdiction	\N
1007473	Salamat	Salamat	1002353	\N	Jurisdiction	\N
1007476	Mayo-Kebbi Ouest	Mayo-Kebbi Ouest	1002353	\N	Jurisdiction	\N
1007477	Batha	Batha	1002353	\N	Jurisdiction	\N
1007479	Barh el Gazel	Barh el Gazel	1002353	\N	Jurisdiction	\N
1007481	Gu??ra	Guera	1002353	\N	Jurisdiction	\N
1007483	Kanem	Kanem	1002353	\N	Jurisdiction	\N
1007484	Tandjil??	Tandjile	1002353	\N	Jurisdiction	\N
1007485	Mandoul	Mandoul	1002353	\N	Jurisdiction	\N
1007488	Kerguelen	Kerguelen	1002387	\N	Jurisdiction	\N
1007489	Maritime	Maritime	1002531	\N	Jurisdiction	\N
1007490	Centrale	Centrale	1002531	\N	Jurisdiction	\N
1007492	Kara	Kara	1002531	\N	Jurisdiction	\N
1007493	Savanes	Savanes	1002531	\N	Jurisdiction	\N
1007496	Phetchaburi	Phetchaburi	1002530	\N	Jurisdiction	\N
1007497	Trang	Trang	1002530	\N	Jurisdiction	\N
1007499	Lampang	Lampang	1002530	\N	Jurisdiction	\N
1007501	Kanchanaburi	Kanchanaburi	1002530	\N	Jurisdiction	\N
1007502	Tak	Tak	1002530	\N	Jurisdiction	\N
1007503	Surat Thani	Surat Thani	1002530	\N	Jurisdiction	\N
1007505	Chiang Mai	Chiang Mai	1002530	\N	Jurisdiction	\N
1007507	Ranong	Ranong	1002530	\N	Jurisdiction	\N
1007509	Lamphun	Lamphun	1002530	\N	Jurisdiction	\N
1007510	Chiang Rai	Chiang Rai	1002530	\N	Jurisdiction	\N
1007513	Krabi	Krabi	1002530	\N	Jurisdiction	\N
1007514	Kamphaeng Phet	Kamphaeng Phet	1002530	\N	Jurisdiction	\N
1007515	Kalasin	Kalasin	1002530	\N	Jurisdiction	\N
1007517	Songkhla	Songkhla	1002530	\N	Jurisdiction	\N
1007520	Changwat Nong Bua Lamphu	Changwat Nong Bua Lamphu	1002530	\N	Jurisdiction	\N
1007521	Yasothon	Yasothon	1002530	\N	Jurisdiction	\N
1007522	Pattani	Pattani	1002530	\N	Jurisdiction	\N
1007523	Yala	Yala	1002530	\N	Jurisdiction	\N
1007527	Loei	Loei	1002530	\N	Jurisdiction	\N
1007528	Phra Nakhon Si Ayutthaya	Phra Nakhon Si Ayutthaya	1002530	\N	Jurisdiction	\N
1007529	Sa Kaeo	Sa Kaeo	1002530	\N	Jurisdiction	\N
1007530	Uttaradit	Uttaradit	1002530	\N	Jurisdiction	\N
1007532	Phichit	Phichit	1002530	\N	Jurisdiction	\N
1007534	Nong Khai	Nong Khai	1002530	\N	Jurisdiction	\N
1007535	Narathiwat	Narathiwat	1002530	\N	Jurisdiction	\N
1007538	Sisaket	Sisaket	1002530	\N	Jurisdiction	\N
1007539	Chon Buri	Chon Buri	1002530	\N	Jurisdiction	\N
1007747	Rivne	Rivne	1002541	\N	Jurisdiction	\N
1007542	Sakon Nakhon	Sakon Nakhon	1002530	\N	Jurisdiction	\N
1007543	Satun	Satun	1002530	\N	Jurisdiction	\N
1007546	Samut Sakhon	Samut Sakhon	1002530	\N	Jurisdiction	\N
1007547	Nakhon Pathom	Nakhon Pathom	1002530	\N	Jurisdiction	\N
1007549	Rayong	Rayong	1002530	\N	Jurisdiction	\N
1007552	Chaiyaphum	Chaiyaphum	1002530	\N	Jurisdiction	\N
1007554	Phitsanulok	Phitsanulok	1002530	\N	Jurisdiction	\N
1007667	Trabzon	Trabzon	1002535	\N	Jurisdiction	\N
1007668	Bursa	Bursa	1002535	\N	Jurisdiction	\N
1007670	Yalova	Yalova	1002535	\N	Jurisdiction	\N
1007672	Edirne	Edirne	1002535	\N	Jurisdiction	\N
1007674	Kastamonu	Kastamonu	1002535	\N	Jurisdiction	\N
1007675	Giresun	Giresun	1002535	\N	Jurisdiction	\N
1007678	??orum	Corum	1002535	\N	Jurisdiction	\N
1007679	Sinop	Sinop	1002535	\N	Jurisdiction	\N
1007680	Kars	Kars	1002535	\N	Jurisdiction	\N
1007683	Rize	Rize	1002535	\N	Jurisdiction	\N
1007684	K??rklareli	Kirklareli	1002535	\N	Jurisdiction	\N
1007686	Artvin	Artvin	1002535	\N	Jurisdiction	\N
1007687	Bolu	Bolu	1002535	\N	Jurisdiction	\N
1007690	Bayburt	Bayburt	1002535	\N	Jurisdiction	\N
1007691	Bart??n	Bartin	1002535	\N	Jurisdiction	\N
1007692	Ardahan	Ardahan	1002535	\N	Jurisdiction	\N
1007695	Sangre Grande	Sangre Grande	1002533	\N	Jurisdiction	\N
1007696	City of San Fernando	City of San Fernando	1002533	\N	Jurisdiction	\N
1007697	Mayaro	Mayaro	1002533	\N	Jurisdiction	\N
1007557	Pathum Thani	Pathum Thani	1002530	\N	Jurisdiction	\N
1007558	Nonthaburi	Nonthaburi	1002530	\N	Jurisdiction	\N
1007560	Nakhon Phanom	Nakhon Phanom	1002530	\N	Jurisdiction	\N
1007562	Mukdahan	Mukdahan	1002530	\N	Jurisdiction	\N
1007564	Lop Buri	Lop Buri	1002530	\N	Jurisdiction	\N
1007565	Bangkok	Bangkok	1002530	\N	Jurisdiction	\N
1007567	Chai Nat	Chai Nat	1002530	\N	Jurisdiction	\N
1007569	Khatlon	Khatlon	1002528	\N	Jurisdiction	\N
1007571	Republican Subordination	Republican Subordination	1002528	\N	Jurisdiction	\N
1007572	Gorno-Badakhshan	Gorno-Badakhshan	1002528	\N	Jurisdiction	\N
1007573	Dushanbe	Dushanbe	1002528	\N	Jurisdiction	\N
1007575	Liqui????	Liquica	1002372	\N	Jurisdiction	\N
1007577	D??li	Dili	1002372	\N	Jurisdiction	\N
1007579	Aileu	Aileu	1002372	\N	Jurisdiction	\N
1007580	Manufahi	Manufahi	1002372	\N	Jurisdiction	\N
1007582	Balkan	Balkan	1002536	\N	Jurisdiction	\N
1007585	Mary	Mary	1002536	\N	Jurisdiction	\N
1007586	Lebap	Lebap	1002536	\N	Jurisdiction	\N
1007587	Zaghw??n	Zaghwan	1002534	\N	Jurisdiction	\N
1007590	Tataouine	Tataouine	1002534	\N	Jurisdiction	\N
1007591	Al Qa??rayn	Al Qasrayn	1002534	\N	Jurisdiction	\N
1007594	S??sah	Susah	1002534	\N	Jurisdiction	\N
1007597	Al Munast??r	Al Munastir	1002534	\N	Jurisdiction	\N
1007598	??af??qis	Safaqis	1002534	\N	Jurisdiction	\N
1007600	Qibil??	Qibili	1002534	\N	Jurisdiction	\N
1007601	Ariana	Ariana	1002534	\N	Jurisdiction	\N
1007604	Madan??n	Madanin	1002534	\N	Jurisdiction	\N
1007605	Banzart	Banzart	1002534	\N	Jurisdiction	\N
1007606	Manouba	Manouba	1002534	\N	Jurisdiction	\N
1007609	Bin ???Ar??s	Bin 'Arus	1002534	\N	Jurisdiction	\N
1007611	Tongatapu	Tongatapu	1002532	\N	Jurisdiction	\N
1007612	Hakk??ri	Hakkari	1002535	\N	Jurisdiction	\N
1007613	Yozgat	Yozgat	1002535	\N	Jurisdiction	\N
1007616	Ayd??n	Aydin	1002535	\N	Jurisdiction	\N
1007617	Mu??la	Mugla	1002535	\N	Jurisdiction	\N
1007619	Kayseri	Kayseri	1002535	\N	Jurisdiction	\N
1007623	Erzincan	Erzincan	1002535	\N	Jurisdiction	\N
1007624	U??ak	Usak	1002535	\N	Jurisdiction	\N
1007626	Nev??ehir	Nevsehir	1002535	\N	Jurisdiction	\N
1007627	Manisa	Manisa	1002535	\N	Jurisdiction	\N
1007630	K??tahya	Kutahya	1002535	\N	Jurisdiction	\N
1007632	Mersin	Mersin	1002535	\N	Jurisdiction	\N
1007633	Bal??kesir	Balikesir	1002535	\N	Jurisdiction	\N
1007636	????rnak	Sirnak	1002535	\N	Jurisdiction	\N
1007637	Diyarbak??r	Diyarbakir	1002535	\N	Jurisdiction	\N
1007639	Konya	Konya	1002535	\N	Jurisdiction	\N
1007641	Denizli	Denizli	1002535	\N	Jurisdiction	\N
1007643	Kahramanmara??	Kahramanmaras	1002535	\N	Jurisdiction	\N
1007644	A??r??	Agri	1002535	\N	Jurisdiction	\N
1007647	Aksaray	Aksaray	1002535	\N	Jurisdiction	\N
1007648	Gaziantep	Gaziantep	1002535	\N	Jurisdiction	\N
1007649	Ni??de	Nigde	1002535	\N	Jurisdiction	\N
1007651	Malatya	Malatya	1002535	\N	Jurisdiction	\N
1007654	Elaz????	Elazig	1002535	\N	Jurisdiction	\N
1007655	K??r??kkale	Kirikkale	1002535	\N	Jurisdiction	\N
1007656	Kilis	Kilis	1002535	\N	Jurisdiction	\N
1007659	I??d??r	Igdir	1002535	\N	Jurisdiction	\N
1007661	Eski??ehir	Eskisehir	1002535	\N	Jurisdiction	\N
1007662	Burdur	Burdur	1002535	\N	Jurisdiction	\N
1007700	San Juan/Laventille	San Juan/Laventille	1002533	\N	Jurisdiction	\N
1007702	Borough of Arima	Borough of Arima	1002533	\N	Jurisdiction	\N
1007703	Funafuti	Funafuti	1002538	\N	Jurisdiction	\N
1007705	Taipei	Taipei	1002527	\N	Jurisdiction	\N
1007706	Kaohsiung	Kaohsiung	1002527	\N	Jurisdiction	\N
1007709	Pemba North	Pemba North	1002529	\N	Jurisdiction	\N
1007710	Mbeya	Mbeya	1002529	\N	Jurisdiction	\N
1007711	Pwani	Pwani	1002529	\N	Jurisdiction	\N
1007713	Kigoma	Kigoma	1002529	\N	Jurisdiction	\N
1007715	Mwanza	Mwanza	1002529	\N	Jurisdiction	\N
1007717	Tabora	Tabora	1002529	\N	Jurisdiction	\N
1007720	Tanga	Tanga	1002529	\N	Jurisdiction	\N
1007721	Rukwa	Rukwa	1002529	\N	Jurisdiction	\N
1007722	Simiyu	Simiyu	1002529	\N	Jurisdiction	\N
1007724	Singida	Singida	1002529	\N	Jurisdiction	\N
1007726	Kagera	Kagera	1002529	\N	Jurisdiction	\N
1007727	Njombe	Njombe	1002529	\N	Jurisdiction	\N
1007729	Manyara	Manyara	1002529	\N	Jurisdiction	\N
1007730	Dodoma	Dodoma	1002529	\N	Jurisdiction	\N
1007733	Iringa	Iringa	1002529	\N	Jurisdiction	\N
1007734	Lindi	Lindi	1002529	\N	Jurisdiction	\N
1007736	Mtwara	Mtwara	1002529	\N	Jurisdiction	\N
1007737	Sumy	Sumy	1002541	\N	Jurisdiction	\N
1007740	Cherkasy	Cherkasy	1002541	\N	Jurisdiction	\N
1007741	Lviv	Lviv	1002541	\N	Jurisdiction	\N
1007743	Kharkiv	Kharkiv	1002541	\N	Jurisdiction	\N
1007745	Vinnyts'ka	Vinnyts'ka	1002541	\N	Jurisdiction	\N
1007748	Odessa	Odessa	1002541	\N	Jurisdiction	\N
1007749	Crimea	Crimea	1002541	\N	Jurisdiction	\N
1007752	Mykolaiv	Mykolaiv	1002541	\N	Jurisdiction	\N
1007753	Volyn	Volyn	1002541	\N	Jurisdiction	\N
1007755	Ternopil	Ternopil	1002541	\N	Jurisdiction	\N
1007758	Misto Sevastopol???	Misto Sevastopol'	1002541	\N	Jurisdiction	\N
1007759	Chernihiv	Chernihiv	1002541	\N	Jurisdiction	\N
1007760	Poltava	Poltava	1002541	\N	Jurisdiction	\N
1007763	Chernivtsi	Chernivtsi	1002541	\N	Jurisdiction	\N
1007764	Northern Region	Northern Region	1002540	\N	Jurisdiction	\N
1007766	Eastern Region	Eastern Region	1002540	\N	Jurisdiction	\N
1007768	Virginia	Virginia	1002544	\N	Jurisdiction	\N
1007769	Alabama	Alabama	1002544	\N	Jurisdiction	\N
1007771	Arkansas	Arkansas	1002544	\N	Jurisdiction	\N
1007773	Delaware	Delaware	1002544	\N	Jurisdiction	\N
1007774	Florida	Florida	1002544	\N	Jurisdiction	\N
1007776	Illinois	Illinois	1002544	\N	Jurisdiction	\N
1007777	Indiana	Indiana	1002544	\N	Jurisdiction	\N
1007779	Louisiana	Louisiana	1002544	\N	Jurisdiction	\N
1007782	Mississippi	Mississippi	1002544	\N	Jurisdiction	\N
1007783	North Carolina	North Carolina	1002544	\N	Jurisdiction	\N
1007784	New Jersey	New Jersey	1002544	\N	Jurisdiction	\N
1007786	Oklahoma	Oklahoma	1002544	\N	Jurisdiction	\N
1007789	Tennessee	Tennessee	1002544	\N	Jurisdiction	\N
1007790	Texas	Texas	1002544	\N	Jurisdiction	\N
1007791	Connecticut	Connecticut	1002544	\N	Jurisdiction	\N
1007792	Iowa	Iowa	1002544	\N	Jurisdiction	\N
1007795	Michigan	Michigan	1002544	\N	Jurisdiction	\N
1007796	Minnesota	Minnesota	1002544	\N	Jurisdiction	\N
1007798	Nebraska	Nebraska	1002544	\N	Jurisdiction	\N
1007800	New York	New York	1002544	\N	Jurisdiction	\N
1007802	South Dakota	South Dakota	1002544	\N	Jurisdiction	\N
1007803	Vermont	Vermont	1002544	\N	Jurisdiction	\N
1007804	Wisconsin	Wisconsin	1002544	\N	Jurisdiction	\N
1007807	Arizona	Arizona	1002544	\N	Jurisdiction	\N
1007808	Colorado	Colorado	1002544	\N	Jurisdiction	\N
1007810	Nevada	Nevada	1002544	\N	Jurisdiction	\N
1007811	Utah	Utah	1002544	\N	Jurisdiction	\N
1007813	Idaho	Idaho	1002544	\N	Jurisdiction	\N
1007815	Oregon	Oregon	1002544	\N	Jurisdiction	\N
1007816	Washington	Washington	1002544	\N	Jurisdiction	\N
1007819	R??o Negro	Rio Negro	1002545	\N	Jurisdiction	\N
1007821	Treinta y Tres	Treinta y Tres	1002545	\N	Jurisdiction	\N
1007822	Tacuaremb??	Tacuarembo	1002545	\N	Jurisdiction	\N
1007825	Maldonado	Maldonado	1002545	\N	Jurisdiction	\N
1007826	Salto	Salto	1002545	\N	Jurisdiction	\N
1007827	Rocha	Rocha	1002545	\N	Jurisdiction	\N
1007830	Montevideo	Montevideo	1002545	\N	Jurisdiction	\N
1007832	Soriano	Soriano	1002545	\N	Jurisdiction	\N
1007833	Cerro Largo	Cerro Largo	1002545	\N	Jurisdiction	\N
1007834	Florida	Florida	1002545	\N	Jurisdiction	\N
1007837	Artigas	Artigas	1002545	\N	Jurisdiction	\N
1007840	Samarqand	Samarqand	1002546	\N	Jurisdiction	\N
1007842	Qashqadaryo	Qashqadaryo	1002546	\N	Jurisdiction	\N
1007843	Bukhara	Bukhara	1002546	\N	Jurisdiction	\N
1007846	Sirdaryo	Sirdaryo	1002546	\N	Jurisdiction	\N
1007847	Navoiy	Navoiy	1002546	\N	Jurisdiction	\N
1007849	Xorazm	Xorazm	1002546	\N	Jurisdiction	\N
1007850	Toshkent Shahri	Toshkent Shahri	1002546	\N	Jurisdiction	\N
1007865	T??chira	Tachira	1002549	\N	Jurisdiction	\N
1007866	Miranda	Miranda	1002549	\N	Jurisdiction	\N
1007867	Zulia	Zulia	1002549	\N	Jurisdiction	\N
1007869	Falc??n	Falcon	1002549	\N	Jurisdiction	\N
1007870	Amazonas	Amazonas	1002549	\N	Jurisdiction	\N
1007871	M??rida	Merida	1002549	\N	Jurisdiction	\N
1007873	Sucre	Sucre	1002549	\N	Jurisdiction	\N
1007874	Capital	Capital	1002549	\N	Jurisdiction	\N
1007876	Apure	Apure	1002549	\N	Jurisdiction	\N
1007878	Saint Croix Island	Saint Croix Island	1002539	\N	Jurisdiction	\N
1007879	Ngh??? An	Nghe An	1002550	\N	Jurisdiction	\N
1007880	Y??n B??i	Yen Bai	1002550	\N	Jurisdiction	\N
1007881	B?? R???a-V??ng T??u	Ba Ria-Vung Tau	1002550	\N	Jurisdiction	\N
1007882	Hau Giang	Hau Giang	1002550	\N	Jurisdiction	\N
1007884	V??nh Long	Vinh Long	1002550	\N	Jurisdiction	\N
1007885	Ph?? Th???	Phu Tho	1002550	\N	Jurisdiction	\N
1007887	Ph?? Y??n	Phu Yen	1002550	\N	Jurisdiction	\N
1007888	Tuy??n Quang	Tuyen Quang	1002550	\N	Jurisdiction	\N
1007889	Tr?? Vinh	Tra Vinh	1002550	\N	Jurisdiction	\N
1007891	Ho Chi Minh City	Ho Chi Minh City	1002550	\N	Jurisdiction	\N
1007892	Thanh H??a	Thanh Hoa	1002550	\N	Jurisdiction	\N
1007893	Th??i Nguy??n	Thai Nguyen	1002550	\N	Jurisdiction	\N
1007895	T??y Ninh	Tay Ninh	1002550	\N	Jurisdiction	\N
1007896	Long An	Long An	1002550	\N	Jurisdiction	\N
1007897	Qu???ng Nam	Quang Nam	1002550	\N	Jurisdiction	\N
1007898	Ha N???i	Ha Noi	1002550	\N	Jurisdiction	\N
1007900	S??c Tr??ng	Soc Trang	1002550	\N	Jurisdiction	\N
1007901	L??o Cai	Lao Cai	1002550	\N	Jurisdiction	\N
1007903	Ki???n Giang	Kien Giang	1002550	\N	Jurisdiction	\N
1007904	B??nh ?????nh	Binh Dinh	1002550	\N	Jurisdiction	\N
1007906	Gia Lai	Gia Lai	1002550	\N	Jurisdiction	\N
1007907	H?? Nam	Ha Nam	1002550	\N	Jurisdiction	\N
1007908	B??nh Thu???n	Binh Thuan	1002550	\N	Jurisdiction	\N
1007909	Ninh Thu???n	Ninh Thuan	1002550	\N	Jurisdiction	\N
1007911	Kh??nh H??a	Khanh Hoa	1002550	\N	Jurisdiction	\N
1007912	Nam ?????nh	Nam Dinh	1002550	\N	Jurisdiction	\N
1007914	An Giang	An Giang	1002550	\N	Jurisdiction	\N
1007915	L???ng S??n	Lang Son	1002550	\N	Jurisdiction	\N
1007916	Kon Tum	Kon Tum	1002550	\N	Jurisdiction	\N
1007918	Th???a Thi??n-Hu???	Thua Thien-Hue	1002550	\N	Jurisdiction	\N
1007919	H??a B??nh	Hoa Binh	1002550	\N	Jurisdiction	\N
1007920	H?? T??nh	Ha Tinh	1002550	\N	Jurisdiction	\N
1007922	H???i D????ng	Hai Duong	1002550	\N	Jurisdiction	\N
1007923	H?? Giang	Ha Giang	1002550	\N	Jurisdiction	\N
1007925	Qu???ng B??nh	Quang Binh	1002550	\N	Jurisdiction	\N
1007926	Qu???ng Tr???	Quang Tri	1002550	\N	Jurisdiction	\N
1007927	T???nh ??i???n Bi??n	Tinh Dien Bien	1002550	\N	Jurisdiction	\N
1007928	???? N???ng	Da Nang	1002550	\N	Jurisdiction	\N
1007930	Cao B???ng	Cao Bang	1002550	\N	Jurisdiction	\N
1007931	C???n Th??	Can Tho	1002550	\N	Jurisdiction	\N
1007932	C?? Mau	Ca Mau	1002550	\N	Jurisdiction	\N
1007934	?????ng Nai	Dong Nai	1002550	\N	Jurisdiction	\N
1007936	B???c Ninh	Bac Ninh	1002550	\N	Jurisdiction	\N
1007938	B???c Giang	Bac Giang	1002550	\N	Jurisdiction	\N
1007939	B???c K???n	Bac Kan	1002550	\N	Jurisdiction	\N
1007940	Shefa	Shefa	1002547	\N	Jurisdiction	\N
1007943	Mitrovica	Mitrovica	1002425	\N	Jurisdiction	\N
1007944	Gjilan	Gjilan	1002425	\N	Jurisdiction	\N
1007945	Ferizaj	Ferizaj	1002425	\N	Jurisdiction	\N
1007948	Pec	Pec	1002425	\N	Jurisdiction	\N
1007950	Abyan	Abyan	1002553	\N	Jurisdiction	\N
1007952	Ibb	Ibb	1002553	\N	Jurisdiction	\N
1007953	Ta???izz	Ta'izz	1002553	\N	Jurisdiction	\N
1007955	??a???dah	Sa'dah	1002553	\N	Jurisdiction	\N
1007956	Ma???rib	Ma'rib	1002553	\N	Jurisdiction	\N
1007957	La???ij	Lahij	1002553	\N	Jurisdiction	\N
1007960	Shabwah	Shabwah	1002553	\N	Jurisdiction	\N
1007963	Al Jawf	Al Jawf	1002553	\N	Jurisdiction	\N
1007965	Aden	Aden	1002553	\N	Jurisdiction	\N
1007966	Mamoudzou	Mamoudzou	1002449	\N	Jurisdiction	\N
1007967	Dzaoudzi	Dzaoudzi	1002449	\N	Jurisdiction	\N
1007968	Koungou	Koungou	1002449	\N	Jurisdiction	\N
1007970	North-West	North-West	1002514	\N	Jurisdiction	\N
1007971	Mpumalanga	Mpumalanga	1002514	\N	Jurisdiction	\N
1007974	Limpopo	Limpopo	1002514	\N	Jurisdiction	\N
1007989	Midlands	Midlands	1002555	\N	Jurisdiction	\N
1007990	Manicaland	Manicaland	1002555	\N	Jurisdiction	\N
1007992	Mashonaland East	Mashonaland East	1002555	\N	Jurisdiction	\N
1007993	Harare	Harare	1002555	\N	Jurisdiction	\N
1007994	Bulawayo	Bulawayo	1002555	\N	Jurisdiction	\N
1007995	Mashonaland Central	Mashonaland Central	1002555	\N	Jurisdiction	\N
1007996	Matabeleland South	Matabeleland South	1002555	\N	Jurisdiction	\N
1007252	Vladimir	Vladimir	1002491	\N	Jurisdiction	\N
\.


--
-- Data for Name: user_object_flags; Type: TABLE DATA; Schema: clause; Owner: syntheia
--

COPY clause.user_object_flags (owner_id, app_user_id, is_favorite, like_status) FROM stdin;
\.


--
-- Data for Name: concepts; Type: TABLE DATA; Schema: concept; Owner: syntheia
--

COPY concept.concepts (concept_id, document_type_id, clause_type_id, mmapi_category_id, mmapi_model_id, needs_training, training_error, is_internal, is_deleted, is_endorsed, mmapi_lastupdated, suite_id, practice_group_id, jurisdiction_id, sector_id, name) FROM stdin;
\.


--
-- Data for Name: document_updates; Type: TABLE DATA; Schema: concept; Owner: syntheia
--

COPY concept.document_updates (document_update_id, doc_id, document_type_id, clause_type_id) FROM stdin;
\.


--
-- Data for Name: activities; Type: TABLE DATA; Schema: public; Owner: syntheia
--

COPY public.activities (activity_id, activity_time, activity_type, app_user_id, activity_data, owner_id) FROM stdin;
\.


--
-- Data for Name: app_users; Type: TABLE DATA; Schema: public; Owner: syntheia
--

COPY public.app_users (app_user_id, firstname, lastname, password, email, user_type, active) FROM stdin;
1	Syntheia	System	$2a$10$rzErxcPh2LG1XlOGDurV3OHIr0wv.aoSiXMhLzxQokfSO/TiNJrdO	system@syntheia.io	5000	t
\.


--
-- Data for Name: job_schedules; Type: TABLE DATA; Schema: public; Owner: syntheia
--

COPY public.job_schedules (job_schedule_id, job_type, job_data, next_time, calc_next_time) FROM stdin;
1021543	GENERAL.UPDATE_CLAUSE_TRIGRAMS	\N	2020-01-10 14:16:41.974201-08	NOW() + INTERVAL '30 minutes'
1024456	MMAPI.SYNC_DOCUMENTS_WITH_MMAPI	\N	2020-01-10 14:16:41.974201-08	NOW() + INTERVAL '30 minutes'
\.


--
-- Data for Name: jobs; Type: TABLE DATA; Schema: public; Owner: syntheia
--

COPY public.jobs (job_id, queued, started, ended, error, job_type, job_data, error_acknowledged) FROM stdin;
\.


--
-- Data for Name: upgrades; Type: TABLE DATA; Schema: public; Owner: syntheia
--

COPY public.upgrades (id, upgradetime, current_id) FROM stdin;
5	2019-07-21 15:19:13.783711-07	1000000
10	2019-07-21 16:31:53.839917-07	1000006
15	2019-07-22 20:43:19.941525-07	1000779
20	2019-08-02 16:27:43.241998-07	1002096
25	2019-08-04 16:14:29.539036-07	1002196
30	2019-08-04 18:53:06.578715-07	1002276
35	2019-08-04 20:59:13.318419-07	1002310
40	2019-08-05 14:20:54.588796-07	1008056
45	2019-08-12 18:55:21.856438-07	1009198
49	2019-08-12 23:01:32.088795-07	1009234
50	2019-08-14 21:55:30.386116-07	1009256
55	2019-08-15 14:24:53.433438-07	1009260
60	2019-08-15 14:24:53.452453-07	1009261
65	2019-08-18 21:47:55.953896-07	1009524
70	2019-08-21 14:44:27.244846-07	1009655
75	2019-08-21 18:20:10.107011-07	1009680
80	2019-08-25 17:26:06.405584-07	1009988
85	2019-08-27 18:24:00.261173-07	1010228
95	2019-08-30 14:55:19.799048-07	1010434
90	2019-08-30 14:56:13.981789-07	1010435
105	2019-09-05 18:18:41.282802-07	1010553
115	2019-09-07 18:02:43.180232-07	1010627
125	2019-09-10 13:23:59.051959-07	1011240
135	2019-09-10 13:23:59.066705-07	1011241
145	2019-09-14 14:51:03.529031-07	1011540
155	2019-09-17 15:21:57.976237-07	1012304
165	2019-09-18 01:28:44.407396-07	1012539
175	2019-09-25 21:23:02.483188-07	1019486
185	2019-09-26 14:47:44.843602-07	1019617
195	2019-09-26 15:07:47.405975-07	1019725
205	2019-09-26 15:34:04.850541-07	1019774
215	2019-09-26 17:13:11.516369-07	1019806
225	2019-09-26 18:19:53.214759-07	1019880
235	2019-09-26 19:55:29.586421-07	1019971
100	2019-10-01 14:31:10.679111-07	1019983
245	2019-10-01 15:27:32.835037-07	1020013
255	2019-10-02 12:20:23.861893-07	1020279
110	2019-10-03 09:50:42.401415-07	1020553
265	2019-10-05 10:45:49.688511-07	1020872
275	2019-10-08 15:53:10.828517-07	1021357
283	2019-10-10 15:12:25.668589-07	1021464
285	2019-10-10 15:12:57.19684-07	1021465
286	2019-10-11 13:15:18.941338-07	1021548
295	2019-10-11 16:08:55.032273-07	1021683
297	2019-10-11 16:38:55.219674-07	1021684
305	2019-10-16 13:44:53.592083-07	1022336
315	2019-10-17 15:51:27.311625-07	1022689
325	2019-10-18 12:50:47.264697-07	1022727
335	2019-10-21 13:11:12.938129-07	1023347
340	2019-10-22 16:28:11.930869-07	1023754
345	2019-10-23 14:22:46.161385-07	1023876
350	2019-10-25 13:29:46.8018-07	1023974
355	2019-10-26 15:39:40.156955-07	1024111
360	2019-10-27 09:36:41.602735-07	1024300
365	2019-10-27 13:40:30.337912-07	1024425
370	2019-10-28 12:49:01.058814-07	1024457
375	2019-11-05 15:16:18.701485-08	1024820
380	2019-11-05 16:11:40.02057-08	1024844
385	2019-11-09 16:12:53.8178-08	1025207
390	2019-11-12 15:35:07.020473-08	1025969
395	2019-11-16 15:29:12.000595-08	1026412
400	2019-11-22 15:41:38.242462-08	1027674
405	2019-11-22 15:50:54.258441-08	1027687
410	2019-12-08 13:10:24.090457-08	1029418
415	2019-12-12 14:13:08.940351-08	1030508
420	2019-12-18 13:26:13.078694-08	1030892
425	2019-12-18 14:03:39.133585-08	1030893
430	2019-12-18 15:10:56.363198-08	1030912
435	2019-12-22 13:35:25.90307-08	1031196
440	2019-12-29 14:17:53.076187-08	1031507
445	2019-12-30 12:54:18.862143-08	1031966
450	2020-01-01 16:05:18.317859-08	1032307
455	2020-01-05 10:01:34.429848-08	1032491
\.


--
-- Name: id_seq; Type: SEQUENCE SET; Schema: public; Owner: syntheia
--

SELECT pg_catalog.setval('public.id_seq', 1032671, true);


--
-- Name: large_id_seq; Type: SEQUENCE SET; Schema: public; Owner: syntheia
--

SELECT pg_catalog.setval('public.large_id_seq', 17718, true);


--
-- Name: clause_word_trigrams clause_word_trigrams_pk; Type: CONSTRAINT; Schema: clause; Owner: syntheia
--

ALTER TABLE ONLY clause.clause_word_trigrams
    ADD CONSTRAINT clause_word_trigrams_pk PRIMARY KEY (word_trigram, clause_type_id);


--
-- Name: clause_word_trigrams_updates clause_word_trigrams_updates_pk; Type: CONSTRAINT; Schema: clause; Owner: syntheia
--

ALTER TABLE ONLY clause.clause_word_trigrams_updates
    ADD CONSTRAINT clause_word_trigrams_updates_pk PRIMARY KEY (clause_word_trigrams_update_id);


--
-- Name: clauses clauses_pk; Type: CONSTRAINT; Schema: clause; Owner: syntheia
--

ALTER TABLE ONLY clause.clauses
    ADD CONSTRAINT clauses_pk PRIMARY KEY (clause_id);


--
-- Name: comments document_comments_pkey; Type: CONSTRAINT; Schema: clause; Owner: syntheia
--

ALTER TABLE ONLY clause.comments
    ADD CONSTRAINT document_comments_pkey PRIMARY KEY (comment_id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: clause; Owner: syntheia
--

ALTER TABLE ONLY clause.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (doc_id);


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: clause; Owner: syntheia
--

ALTER TABLE ONLY clause.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (tag_id);


--
-- Name: user_object_flags user_object_flags_pk; Type: CONSTRAINT; Schema: clause; Owner: syntheia
--

ALTER TABLE ONLY clause.user_object_flags
    ADD CONSTRAINT user_object_flags_pk PRIMARY KEY (owner_id, app_user_id);


--
-- Name: concepts concepts_pk; Type: CONSTRAINT; Schema: concept; Owner: syntheia
--

ALTER TABLE ONLY concept.concepts
    ADD CONSTRAINT concepts_pk PRIMARY KEY (concept_id);


--
-- Name: document_updates document_updates_pk; Type: CONSTRAINT; Schema: concept; Owner: syntheia
--

ALTER TABLE ONLY concept.document_updates
    ADD CONSTRAINT document_updates_pk PRIMARY KEY (document_update_id);


--
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: public; Owner: syntheia
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (activity_id);


--
-- Name: app_users app_users_pk; Type: CONSTRAINT; Schema: public; Owner: syntheia
--

ALTER TABLE ONLY public.app_users
    ADD CONSTRAINT app_users_pk PRIMARY KEY (app_user_id);


--
-- Name: job_schedules job_schedule_pk; Type: CONSTRAINT; Schema: public; Owner: syntheia
--

ALTER TABLE ONLY public.job_schedules
    ADD CONSTRAINT job_schedule_pk PRIMARY KEY (job_schedule_id);


--
-- Name: jobs jobs_pk; Type: CONSTRAINT; Schema: public; Owner: syntheia
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_pk PRIMARY KEY (job_id);


--
-- Name: upgrades upgrades_pkey; Type: CONSTRAINT; Schema: public; Owner: syntheia
--

ALTER TABLE ONLY public.upgrades
    ADD CONSTRAINT upgrades_pkey PRIMARY KEY (id);


--
-- Name: clause_document_link_idx_clause_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX clause_document_link_idx_clause_id ON clause.clause_document_link USING btree (clause_id);


--
-- Name: clause_document_link_un; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE UNIQUE INDEX clause_document_link_un ON clause.clause_document_link USING btree (document_id, clause_id, COALESCE(parent_clause_id, '-1'::integer));


--
-- Name: clauses_idx_author_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX clauses_idx_author_id ON clause.clauses USING gin (author_id);


--
-- Name: clauses_idx_clause_type_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX clauses_idx_clause_type_id ON clause.clauses USING gin (clause_type_id);


--
-- Name: clauses_idx_client_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX clauses_idx_client_id ON clause.clauses USING gin (client_id);


--
-- Name: clauses_idx_document_type_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX clauses_idx_document_type_id ON clause.clauses USING gin (document_type_id);


--
-- Name: clauses_idx_jurisdiction_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX clauses_idx_jurisdiction_id ON clause.clauses USING gin (jurisdiction_id);


--
-- Name: clauses_idx_practice_group_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX clauses_idx_practice_group_id ON clause.clauses USING gin (practice_group_id);


--
-- Name: clauses_idx_sector_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX clauses_idx_sector_id ON clause.clauses USING gin (sector_id);


--
-- Name: clauses_un_hash; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE UNIQUE INDEX clauses_un_hash ON clause.clauses USING btree (hash) WHERE (NOT is_deleted);


--
-- Name: clauses_un_lip_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE UNIQUE INDEX clauses_un_lip_id ON clause.clauses USING btree (lip_id);


--
-- Name: comments_idx_app_user_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX comments_idx_app_user_id ON clause.comments USING btree (app_user_id);


--
-- Name: comments_idx_owner_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX comments_idx_owner_id ON clause.comments USING btree (owner_id);


--
-- Name: documents_idx_author_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX documents_idx_author_id ON clause.documents USING gin (author_id);


--
-- Name: documents_idx_client_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX documents_idx_client_id ON clause.documents USING gin (client_id);


--
-- Name: documents_idx_document_type_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX documents_idx_document_type_id ON clause.documents USING gin (document_type_id);


--
-- Name: documents_idx_jurisdiction_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX documents_idx_jurisdiction_id ON clause.documents USING gin (jurisdiction_id);


--
-- Name: documents_idx_party_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX documents_idx_party_id ON clause.documents USING gin (party_id);


--
-- Name: documents_idx_practice_group_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX documents_idx_practice_group_id ON clause.documents USING gin (practice_group_id);


--
-- Name: documents_idx_sector_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX documents_idx_sector_id ON clause.documents USING gin (sector_id);


--
-- Name: documents_un_chain_version; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE UNIQUE INDEX documents_un_chain_version ON clause.documents USING btree (doc_chain_id, doc_version);


--
-- Name: documents_un_hash; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX documents_un_hash ON clause.documents USING btree (hash);


--
-- Name: documents_un_lip_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE UNIQUE INDEX documents_un_lip_id ON clause.documents USING btree (lip_id);


--
-- Name: documents_un_mmapi_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE UNIQUE INDEX documents_un_mmapi_id ON clause.documents USING btree (mmapi_id) WHERE (mmapi_id IS NOT NULL);


--
-- Name: tags_idx_parent_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX tags_idx_parent_id ON clause.tags USING btree (parent_id);


--
-- Name: tags_un_tag_name; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE UNIQUE INDEX tags_un_tag_name ON clause.tags USING btree (tag_name, COALESCE(parent_id, '-1'::integer), tag_type);


--
-- Name: user_object_flags_idx_app_user_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX user_object_flags_idx_app_user_id ON clause.user_object_flags USING btree (app_user_id);


--
-- Name: user_object_flags_idx_owner_id; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE INDEX user_object_flags_idx_owner_id ON clause.user_object_flags USING btree (owner_id);


--
-- Name: user_object_flags_un; Type: INDEX; Schema: clause; Owner: syntheia
--

CREATE UNIQUE INDEX user_object_flags_un ON clause.user_object_flags USING btree (owner_id, app_user_id);


--
-- Name: concepts_un_document_type_id_clause_type_id; Type: INDEX; Schema: concept; Owner: syntheia
--

CREATE UNIQUE INDEX concepts_un_document_type_id_clause_type_id ON concept.concepts USING btree (document_type_id, clause_type_id) WHERE is_internal;


--
-- Name: concepts_un_mmapi_category_id; Type: INDEX; Schema: concept; Owner: syntheia
--

CREATE UNIQUE INDEX concepts_un_mmapi_category_id ON concept.concepts USING btree (mmapi_category_id) WHERE (NOT is_deleted);


--
-- Name: concepts_un_mmapi_model_id; Type: INDEX; Schema: concept; Owner: syntheia
--

CREATE UNIQUE INDEX concepts_un_mmapi_model_id ON concept.concepts USING btree (mmapi_model_id) WHERE (NOT is_deleted);


--
-- Name: concepts_un_name; Type: INDEX; Schema: concept; Owner: syntheia
--

CREATE UNIQUE INDEX concepts_un_name ON concept.concepts USING btree (name) WHERE ((NOT is_deleted) AND (NOT is_internal));


--
-- Name: activities_idx_app_user_id; Type: INDEX; Schema: public; Owner: syntheia
--

CREATE INDEX activities_idx_app_user_id ON public.activities USING btree (app_user_id);


--
-- Name: activities_idx_owner_id; Type: INDEX; Schema: public; Owner: syntheia
--

CREATE INDEX activities_idx_owner_id ON public.activities USING btree (owner_id);


--
-- Name: app_users_un_email; Type: INDEX; Schema: public; Owner: syntheia
--

CREATE UNIQUE INDEX app_users_un_email ON public.app_users USING btree (email) WHERE active;


--
-- Name: jobs_pending_new_error_idx; Type: INDEX; Schema: public; Owner: syntheia
--

CREATE INDEX jobs_pending_new_error_idx ON public.jobs USING btree (job_id) WHERE (((ended IS NULL) OR (error IS NOT NULL)) AND (error_acknowledged IS NOT TRUE));


--
-- Name: jobs_waiting_idx; Type: INDEX; Schema: public; Owner: syntheia
--

CREATE INDEX jobs_waiting_idx ON public.jobs USING btree (job_id) WHERE ((started IS NULL) AND (ended IS NULL));


--
-- Name: tags tags_unaccent_tr; Type: TRIGGER; Schema: clause; Owner: syntheia
--

CREATE TRIGGER tags_unaccent_tr BEFORE INSERT OR UPDATE ON clause.tags FOR EACH ROW EXECUTE PROCEDURE clause.tags_unaccent_tr();


--
-- Name: comments comments_fk_app_user_id; Type: FK CONSTRAINT; Schema: clause; Owner: syntheia
--

ALTER TABLE ONLY clause.comments
    ADD CONSTRAINT comments_fk_app_user_id FOREIGN KEY (app_user_id) REFERENCES public.app_users(app_user_id);


--
-- Name: user_object_flags practice_groups_fk_app_user_id; Type: FK CONSTRAINT; Schema: clause; Owner: syntheia
--

ALTER TABLE ONLY clause.user_object_flags
    ADD CONSTRAINT practice_groups_fk_app_user_id FOREIGN KEY (app_user_id) REFERENCES public.app_users(app_user_id);


--
-- Name: tags tags_fk_parent_id; Type: FK CONSTRAINT; Schema: clause; Owner: syntheia
--

ALTER TABLE ONLY clause.tags
    ADD CONSTRAINT tags_fk_parent_id FOREIGN KEY (parent_id) REFERENCES clause.tags(tag_id);


--
-- Name: activities activities_fk_app_user_id; Type: FK CONSTRAINT; Schema: public; Owner: syntheia
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_fk_app_user_id FOREIGN KEY (app_user_id) REFERENCES public.app_users(app_user_id);

--
-- PostgreSQL database dump complete
--

