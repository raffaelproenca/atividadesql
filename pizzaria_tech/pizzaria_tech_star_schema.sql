-- PARTE 1 - CONSTRUÇÃO DO MODELO DIMENSIONAL

-- MISSÃO 01
CREATE DATABASE IF NOT EXISTS bd_pizzaria_tech CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE bd_pizzaria_tech;

CREATE TABLE dim_cliente (
    id_cliente INT NOT NULL AUTO_INCREMENT,
    nome_cliente VARCHAR(100) NOT NULL,
    cidade VARCHAR(100) NOT NULL,
    estado VARCHAR(2) NOT NULL,
    PRIMARY KEY (id_cliente)
) ENGINE=InnoDB;

CREATE TABLE dim_produto (
    id_produto INT NOT NULL AUTO_INCREMENT,
    nome_produto VARCHAR(100) NOT NULL,
    categoria VARCHAR(50) NOT NULL,
    preco_unitario DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (id_produto)
) ENGINE=InnoDB;

CREATE TABLE dim_vendedor (
    id_vendedor INT NOT NULL AUTO_INCREMENT,
    nome_vendedor VARCHAR(100) NOT NULL,
    turno VARCHAR(20) NOT NULL,
    filial VARCHAR(50) NOT NULL,
    PRIMARY KEY (id_vendedor)
) ENGINE=InnoDB;

CREATE TABLE dim_tempo (
    id_tempo INT NOT NULL AUTO_INCREMENT,
    data_venda DATE NOT NULL,
    dia INT NOT NULL,
    mes INT NOT NULL,
    nome_mes VARCHAR(20) NOT NULL,
    ano INT NOT NULL,
    dia_semana VARCHAR(20) NOT NULL,
    PRIMARY KEY (id_tempo)
) ENGINE=InnoDB;

CREATE TABLE fact_venda (
    id_venda INT NOT NULL AUTO_INCREMENT,
    id_cliente INT NOT NULL,
    id_produto INT NOT NULL,
    id_vendedor INT NOT NULL,
    id_tempo INT NOT NULL,
    quantidade INT NOT NULL,
    valor_total DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (id_venda),
    CONSTRAINT fk_fact_cliente FOREIGN KEY (id_cliente)
        REFERENCES dim_cliente (id_cliente)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_fact_produto FOREIGN KEY (id_produto)
        REFERENCES dim_produto (id_produto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_fact_vendedor FOREIGN KEY (id_vendedor)
        REFERENCES dim_vendedor (id_vendedor)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_fact_tempo FOREIGN KEY (id_tempo)
        REFERENCES dim_tempo (id_tempo)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;


-- PARTE 3 - INTELIGÊNCIA DE NEGÓCIOS COM SQL

-- MISSÃO 03
SELECT
    v.filial,
    p.nome_produto AS pizza,
    SUM(f.quantidade) AS unidades_vendidas
FROM fact_venda f
JOIN dim_vendedor v ON v.id_vendedor = f.id_vendedor
JOIN dim_produto  p ON p.id_produto  = f.id_produto
GROUP BY v.filial, p.id_produto, p.nome_produto
ORDER BY v.filial, unidades_vendidas DESC, p.nome_produto;

-- MISSÃO 04
SELECT
    t.dia_semana,
    SUM(f.quantidade)  AS unidades_vendidas,
    SUM(f.valor_total) AS faturamento_total
FROM fact_venda f
JOIN dim_tempo t ON t.id_tempo = f.id_tempo
GROUP BY t.dia_semana
ORDER BY faturamento_total DESC;

-- MISSÃO 05
SELECT
    v.nome_vendedor,
    v.filial,
    v.turno,
    SUM(f.quantidade)  AS unidades_vendidas,
    SUM(f.valor_total) AS faturamento_total
FROM fact_venda f
JOIN dim_vendedor v ON v.id_vendedor = f.id_vendedor
GROUP BY v.id_vendedor, v.nome_vendedor, v.filial, v.turno
ORDER BY faturamento_total DESC;

-- MISSÃO 06
SELECT
    c.cidade,
    COUNT(*)                      AS qtd_registros_venda,
    SUM(f.valor_total)            AS faturamento_total,
    ROUND(AVG(f.valor_total), 2)  AS ticket_medio
FROM fact_venda f
JOIN dim_cliente c ON c.id_cliente = f.id_cliente
GROUP BY c.cidade
ORDER BY ticket_medio DESC;
