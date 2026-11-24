CREATE DATABASE IF NOT EXISTS db_sp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- PARTE 1 - PROCEDURE SILVER
DROP PROCEDURE IF EXISTS db_sp.sp_carregar_silver;
DELIMITER $$
CREATE PROCEDURE db_sp.sp_carregar_silver()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_vendas_tratadas;
        RESIGNAL;
    END;

    DROP TEMPORARY TABLE IF EXISTS tmp_vendas_tratadas;

    START TRANSACTION;

    DELETE FROM db_silver.tb_vendas_rejeitadas;
    DELETE FROM db_silver.tb_vendas;
    DELETE FROM db_silver.tb_clientes;

    INSERT INTO db_silver.tb_clientes
        (id_cliente, nome, email, status_email, cidade, data_cadastro)
    SELECT
        c.id_cliente,
        c.nome,
        CASE
            WHEN TRIM(c.email) REGEXP '^[^@ ]+@[^@ ]+[.][^@ ]+$' THEN TRIM(c.email)
            WHEN TRIM(c.email) REGEXP '^[^@ ]+@gmail$'           THEN CONCAT(TRIM(c.email), '.com')
            ELSE NULL
        END,
        CASE
            WHEN TRIM(c.email) REGEXP '^[^@ ]+@[^@ ]+[.][^@ ]+$' THEN 'VALIDO'
            WHEN TRIM(c.email) REGEXP '^[^@ ]+@gmail$'           THEN 'CORRIGIDO'
            ELSE 'INVALIDO'
        END,
        c.cidade,
        CASE
            WHEN TRIM(c.data_cadastro) REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'  THEN STR_TO_DATE(TRIM(c.data_cadastro), '%Y-%m-%d')
            WHEN TRIM(c.data_cadastro) REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'  THEN STR_TO_DATE(TRIM(c.data_cadastro), '%Y/%m/%d')
            WHEN TRIM(c.data_cadastro) REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'  THEN STR_TO_DATE(TRIM(c.data_cadastro), '%d-%m-%Y')
            WHEN TRIM(c.data_cadastro) REGEXP '^[0-9]{4}[.][0-9]{2}[.][0-9]{2}$' THEN STR_TO_DATE(TRIM(c.data_cadastro), '%Y.%m.%d')
            ELSE NULL
        END
    FROM db_bronze.tb_clientes_raw c;

    CREATE TEMPORARY TABLE tmp_vendas_tratadas AS
    SELECT
        x.id_venda,
        x.id_cliente,
        x.valor_venda_original,
        x.data_venda_original,
        x.produto,
        CASE WHEN x.valor_norm REGEXP '^-?[0-9]+([.][0-9]+)?$'
             THEN CAST(x.valor_norm AS DECIMAL(12,2)) END                AS valor,
        CASE
            WHEN x.dt REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'     THEN STR_TO_DATE(x.dt, '%Y-%m-%d')
            WHEN x.dt REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'     THEN STR_TO_DATE(x.dt, '%Y/%m/%d')
            WHEN x.dt REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'     THEN STR_TO_DATE(x.dt, '%d-%m-%Y')
            WHEN x.dt REGEXP '^[0-9]{4}[.][0-9]{2}[.][0-9]{2}$' THEN STR_TO_DATE(x.dt, '%Y.%m.%d')
            ELSE NULL
        END                                                             AS data,
        EXISTS (SELECT 1 FROM db_silver.tb_clientes sc
                WHERE sc.id_cliente = x.id_cliente)                     AS cliente_existe,
        (x.valor_norm REGEXP '^-?[0-9]+([.][0-9]+)?$')                  AS valor_numerico
    FROM (
        SELECT
            v.id_venda,
            v.id_cliente,
            v.valor_venda  AS valor_venda_original,
            v.data_venda   AS data_venda_original,
            v.produto,
            TRIM(v.data_venda) AS dt,
            CASE WHEN TRIM(v.valor_venda) LIKE '%,%'
                 THEN REPLACE(REPLACE(TRIM(v.valor_venda), '.', ''), ',', '.')
                 ELSE TRIM(v.valor_venda)
            END AS valor_norm
        FROM db_bronze.tb_vendas_raw v
    ) x;

    INSERT INTO db_silver.tb_vendas (id_venda, id_cliente, valor_venda, data_venda, produto)
    SELECT id_venda, id_cliente, valor, data, produto
    FROM tmp_vendas_tratadas
    WHERE cliente_existe = 1
      AND valor_numerico = 1
      AND valor > 0
      AND data IS NOT NULL;

    INSERT INTO db_silver.tb_vendas_rejeitadas
        (id_venda, id_cliente, valor_venda_original, data_venda_original, produto, motivo)
    SELECT
        id_venda, id_cliente, valor_venda_original, data_venda_original, produto,
        CASE
            WHEN cliente_existe = 0   THEN 'CLIENTE_INEXISTENTE'
            WHEN valor_numerico = 0   THEN 'VALOR_INVALIDO'
            WHEN valor <= 0           THEN 'VALOR_NAO_POSITIVO'
            ELSE                           'DATA_INVALIDA'
        END
    FROM tmp_vendas_tratadas
    WHERE NOT (cliente_existe = 1 AND valor_numerico = 1 AND valor > 0 AND data IS NOT NULL);

    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_vendas_tratadas;
END $$
DELIMITER ;

-- PARTE 2 - PROCEDURE GOLD
DROP PROCEDURE IF EXISTS db_sp.sp_carregar_gold;
DELIMITER $$
CREATE PROCEDURE db_sp.sp_carregar_gold()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_resumo_vendas;
        RESIGNAL;
    END;

    DROP TEMPORARY TABLE IF EXISTS tmp_resumo_vendas;

    CREATE TEMPORARY TABLE tmp_resumo_vendas AS
    SELECT
        c.id_cliente,
        c.nome                                       AS nome_cliente,
        COALESCE(SUM(v.valor_venda), 0)              AS total_vendas,
        COUNT(v.id_venda)                            AS qtd_vendas,
        ROUND(COALESCE(AVG(v.valor_venda), 0), 2)    AS ticket_medio
    FROM db_silver.tb_clientes c
    LEFT JOIN db_silver.tb_vendas v ON v.id_cliente = c.id_cliente
    GROUP BY c.id_cliente, c.nome;

    START TRANSACTION;

    DELETE FROM db_gold.tb_relatorio_vendas;

    INSERT INTO db_gold.tb_relatorio_vendas
        (id_cliente, nome_cliente, total_vendas, qtd_vendas, ticket_medio)
    SELECT id_cliente, nome_cliente, total_vendas, qtd_vendas, ticket_medio
    FROM tmp_resumo_vendas;

    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_resumo_vendas;
END $$
DELIMITER ;

-- PARTE 3 - CONSULTAS DE VALIDAÇÃO

-- TESTE 1
CALL db_sp.sp_carregar_silver();
SELECT * FROM db_silver.tb_clientes ORDER BY id_cliente;
SELECT * FROM db_silver.tb_vendas ORDER BY id_venda;
SELECT * FROM db_silver.tb_vendas_rejeitadas ORDER BY id_venda;

-- TESTE 2
CALL db_sp.sp_carregar_gold();
SELECT * FROM db_gold.tb_relatorio_vendas ORDER BY total_vendas DESC;

-- TESTE 3
CALL db_sp.sp_carregar_silver();
CALL db_sp.sp_carregar_gold();
SELECT
    (SELECT COUNT(*) FROM db_silver.tb_clientes)         AS clientes_silver,
    (SELECT COUNT(*) FROM db_silver.tb_vendas)           AS vendas_validas,
    (SELECT COUNT(*) FROM db_silver.tb_vendas_rejeitadas) AS vendas_rejeitadas,
    (SELECT COUNT(*) FROM db_gold.tb_relatorio_vendas)   AS linhas_gold;

-- TESTE 4

-- 4.1
SELECT id_cliente, nome_cliente, total_vendas
FROM db_gold.tb_relatorio_vendas
ORDER BY total_vendas DESC
LIMIT 3;

-- 4.2
SELECT id_cliente, nome_cliente, ticket_medio
FROM db_gold.tb_relatorio_vendas
WHERE ticket_medio = (SELECT MAX(ticket_medio) FROM db_gold.tb_relatorio_vendas);

-- 4.3
SELECT id_cliente, nome_cliente
FROM db_gold.tb_relatorio_vendas
WHERE qtd_vendas = 0
ORDER BY id_cliente;

-- 4.4
SELECT SUM(valor_venda) AS faturamento_silver FROM db_silver.tb_vendas;

-- 4.5
SELECT SUM(total_vendas) AS faturamento_gold FROM db_gold.tb_relatorio_vendas;

-- 4.6
SELECT
    (SELECT SUM(valor_venda)  FROM db_silver.tb_vendas)            AS faturamento_silver,
    (SELECT SUM(total_vendas) FROM db_gold.tb_relatorio_vendas)    AS faturamento_gold,
    (SELECT SUM(valor_venda)  FROM db_silver.tb_vendas)
      = (SELECT SUM(total_vendas) FROM db_gold.tb_relatorio_vendas) AS conciliado;

-- APOIO
SELECT status_email, COUNT(*) AS clientes FROM db_silver.tb_clientes GROUP BY status_email;
SELECT motivo, COUNT(*) AS vendas FROM db_silver.tb_vendas_rejeitadas GROUP BY motivo ORDER BY motivo;
