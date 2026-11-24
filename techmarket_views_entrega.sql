-- ETAPA 1 - PREPARAÇÃO DO AMBIENTE
USE db_techmarket;

-- ETAPA 2 - CONSTRUÇÃO DAS VIEWS

-- MISSÃO 1
CREATE OR REPLACE VIEW vw_vendas_detalhadas AS
SELECT
    p.id_pedido,
    p.data_pedido,
    c.id_cliente,
    c.nome                                   AS cliente,
    c.cidade,
    c.estado,
    v.id_vendedor,
    v.nome                                   AS vendedor,
    v.equipe,
    pr.id_produto,
    pr.descricao                             AS produto,
    pr.categoria,
    i.id_item,
    i.quantidade,
    i.preco_unitario,
    i.desconto_percentual,
    ROUND(i.quantidade * i.preco_unitario, 2)                                        AS valor_bruto,
    ROUND(i.quantidade * i.preco_unitario * i.desconto_percentual / 100, 2)          AS valor_desconto,
    ROUND(i.quantidade * i.preco_unitario, 2)
      - ROUND(i.quantidade * i.preco_unitario * i.desconto_percentual / 100, 2)      AS valor_faturado
FROM pedidos p
JOIN clientes     c  ON c.id_cliente  = p.id_cliente
JOIN vendedores   v  ON v.id_vendedor = p.id_vendedor
JOIN itens_pedido i  ON i.id_pedido   = p.id_pedido
JOIN produtos     pr ON pr.id_produto = i.id_produto
WHERE p.status_pedido = 'Faturado';

-- 1.1
SELECT *
FROM vw_vendas_detalhadas
ORDER BY valor_faturado DESC;

-- 1.2
SELECT id_pedido, cliente, produto, valor_faturado
FROM vw_vendas_detalhadas
ORDER BY valor_faturado DESC
LIMIT 5;

-- 1.3
SELECT id_pedido, data_pedido, cliente, cidade, produto, valor_faturado
FROM vw_vendas_detalhadas
WHERE estado = 'PR'
ORDER BY data_pedido, id_pedido;

-- MISSÃO 2
CREATE OR REPLACE VIEW vw_desempenho_vendedores AS
SELECT
    v.id_vendedor,
    v.nome                                  AS vendedor,
    v.equipe,
    COUNT(DISTINCT d.id_pedido)             AS qtd_pedidos,
    COALESCE(SUM(d.quantidade), 0)          AS unidades_vendidas,
    COALESCE(SUM(d.valor_faturado), 0)      AS faturamento
FROM vendedores v
LEFT JOIN vw_vendas_detalhadas d ON d.id_vendedor = v.id_vendedor
GROUP BY v.id_vendedor, v.nome, v.equipe;

-- 2.1
SELECT
    vendedor,
    equipe,
    qtd_pedidos,
    faturamento,
    ROUND(faturamento / NULLIF(qtd_pedidos, 0), 2) AS ticket_medio
FROM vw_desempenho_vendedores
ORDER BY faturamento DESC;

-- 2.2
SELECT
    equipe,
    SUM(qtd_pedidos) AS qtd_pedidos,
    SUM(faturamento) AS faturamento_total
FROM vw_desempenho_vendedores
GROUP BY equipe
ORDER BY faturamento_total DESC;

-- MISSÃO 3
CREATE OR REPLACE VIEW vw_desempenho_produtos AS
SELECT
    pr.id_produto,
    pr.descricao                            AS produto,
    pr.categoria,
    COALESCE(SUM(d.quantidade), 0)          AS unidades_vendidas,
    COUNT(DISTINCT d.id_pedido)             AS qtd_pedidos,
    COALESCE(SUM(d.valor_faturado), 0)      AS receita
FROM produtos pr
LEFT JOIN vw_vendas_detalhadas d ON d.id_produto = pr.id_produto
GROUP BY pr.id_produto, pr.descricao, pr.categoria;

-- 3.1
SELECT produto, unidades_vendidas, receita
FROM vw_desempenho_produtos
ORDER BY receita DESC;

-- 3.2
SELECT
    categoria,
    SUM(unidades_vendidas) AS unidades_vendidas,
    SUM(receita)           AS faturamento
FROM vw_desempenho_produtos
GROUP BY categoria
HAVING SUM(receita) > 2000
ORDER BY faturamento DESC;

-- 3.3
SELECT
    produto,
    categoria,
    ROUND(receita / unidades_vendidas, 2) AS valor_medio_por_unidade
FROM vw_desempenho_produtos
WHERE unidades_vendidas > 0
ORDER BY valor_medio_por_unidade DESC
LIMIT 3;

-- MISSÃO 4
CREATE OR REPLACE VIEW vw_resumo_clientes AS
SELECT
    c.id_cliente,
    c.nome                                  AS cliente,
    c.cidade,
    c.estado,
    COUNT(DISTINCT d.id_pedido)             AS qtd_pedidos,
    COALESCE(SUM(d.valor_faturado), 0)      AS valor_total
FROM clientes c
LEFT JOIN vw_vendas_detalhadas d ON d.id_cliente = c.id_cliente
GROUP BY c.id_cliente, c.nome, c.cidade, c.estado;

-- 4.1
SELECT
    cliente,
    estado,
    qtd_pedidos,
    valor_total,
    ROUND(valor_total / NULLIF(qtd_pedidos, 0), 2) AS ticket_medio
FROM vw_resumo_clientes
ORDER BY valor_total DESC;

-- 4.2
SELECT
    cliente,
    valor_total,
    CASE
        WHEN valor_total >= 5000 THEN 'VIP'
        WHEN valor_total > 0     THEN 'Regular'
        ELSE 'Sem compras'
    END AS classificacao
FROM vw_resumo_clientes
ORDER BY valor_total DESC;

-- 4.3
SELECT
    estado,
    SUM(valor_total)            AS faturamento_total,
    COUNT(*)                    AS clientes_cadastrados,
    ROUND(AVG(valor_total), 2)  AS media_por_cliente
FROM vw_resumo_clientes
GROUP BY estado
ORDER BY faturamento_total DESC;

-- ETAPA 3 - INTEGRAÇÃO DE VIEWS

-- MISSÃO 5

-- 5.1
SELECT
    equipe,
    SUM(qtd_pedidos)                                          AS qtd_pedidos,
    SUM(faturamento)                                          AS faturamento,
    ROUND(SUM(faturamento) / NULLIF(SUM(qtd_pedidos), 0), 2)  AS ticket_medio
FROM vw_desempenho_vendedores
GROUP BY equipe
ORDER BY faturamento DESC;

-- 5.2
SELECT
    categoria,
    SUM(receita) AS faturamento,
    ROUND(100 * SUM(receita) / (SELECT SUM(receita) FROM vw_desempenho_produtos), 2) AS percentual_participacao
FROM vw_desempenho_produtos
GROUP BY categoria
ORDER BY faturamento DESC;

-- 5.3
SELECT
    cliente,
    estado,
    valor_total,
    ROUND(valor_total - (SELECT AVG(valor_total) FROM vw_resumo_clientes WHERE qtd_pedidos > 0), 2) AS diferenca_para_media
FROM vw_resumo_clientes
WHERE valor_total > (SELECT AVG(valor_total) FROM vw_resumo_clientes WHERE qtd_pedidos > 0)
ORDER BY valor_total DESC;

-- ETAPA 4 - MANUTENÇÃO E ANÁLISE TÉCNICA

-- MISSÃO 6
CREATE OR REPLACE VIEW vw_desempenho_vendedores AS
SELECT
    v.id_vendedor,
    v.nome                                  AS vendedor,
    v.equipe,
    COUNT(DISTINCT d.id_pedido)             AS qtd_pedidos,
    COALESCE(SUM(d.quantidade), 0)          AS unidades_vendidas,
    COALESCE(SUM(d.valor_faturado), 0)      AS faturamento,
    COALESCE(SUM(d.valor_desconto), 0)      AS desconto_total
FROM vendedores v
LEFT JOIN vw_vendas_detalhadas d ON d.id_vendedor = v.id_vendedor
GROUP BY v.id_vendedor, v.nome, v.equipe;

-- 6.1
SELECT vendedor, equipe, faturamento, desconto_total
FROM vw_desempenho_vendedores
ORDER BY desconto_total DESC;

-- 6.2 (reexecução do 2.1)
SELECT vendedor, equipe, qtd_pedidos, faturamento,
       ROUND(faturamento / NULLIF(qtd_pedidos, 0), 2) AS ticket_medio
FROM vw_desempenho_vendedores
ORDER BY faturamento DESC;

-- 6.3 (reexecução do 2.2)
SELECT equipe, SUM(qtd_pedidos) AS qtd_pedidos, SUM(faturamento) AS faturamento_total
FROM vw_desempenho_vendedores
GROUP BY equipe
ORDER BY faturamento_total DESC;

-- 6.4 (reexecução do 5.1)
SELECT equipe, SUM(qtd_pedidos) AS qtd_pedidos, SUM(faturamento) AS faturamento,
       ROUND(SUM(faturamento) / NULLIF(SUM(qtd_pedidos), 0), 2) AS ticket_medio
FROM vw_desempenho_vendedores
GROUP BY equipe
ORDER BY faturamento DESC;
