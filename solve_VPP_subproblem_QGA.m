%% 量子遗传算法求解VPP子问题
% 保持量子遗传算法作为子函数调用的结构

function solution = solve_VPP_subproblem_QGA(VPP_data, lambda, hour)
    
    % 提取VPP数据
    gen_data = VPP_data.gen_data;
    load_data = VPP_data.load_data;
    gen_buses = VPP_data.gen_buses;
    
    % 发电机约束
    num_gens = size(gen_data, 1);
    Pmin = gen_data(:, 10);  % 最小出力
    Pmax = gen_data(:, 9);   % 最大出力
    
    % 量子遗传算法参数
    QGA_params = struct();
    QGA_params.pop_size = 30;      % 量子种群大小
    QGA_params.max_gen = 50;       % 最大代数
    QGA_params.prob_size = num_gens; % 问题维度
    QGA_params.bounds = [Pmin, Pmax]; % 变量边界
    
    % 目标函数（VPP内部优化目标）
    objective_func = @(P) calculate_VPP_objective(P, gen_data, lambda, gen_buses);
    
    % 调用量子遗传算法
    [best_solution, best_fitness, convergence] = quantum_genetic_algorithm(objective_func, QGA_params);
    
    % 计算可中断负荷
    interruptible_reduction = 0;
    if isfield(VPP_data, 'interruptible_load') && VPP_data.interruptible_load > 0
        % 根据电价决定是否中断负荷
        avg_lambda = mean(lambda(gen_buses));
        if avg_lambda > 40 % 电价高于40$/MWh时考虑中断负荷
            interruptible_reduction = min(VPP_data.interruptible_load, ...
                                        VPP_data.interruptible_load * (avg_lambda - 40) / 60);
        end
    end
    
    % 组织解
    solution = struct();
    solution.gen_output = best_solution;
    solution.interruptible_reduction = interruptible_reduction;
    solution.cost = calculate_VPP_generation_cost(best_solution, gen_data) + ...
                   interruptible_reduction * VPP_data.interruption_cost;
    solution.fitness = best_fitness;
    solution.convergence = convergence;
    
end

%% VPP目标函数
function obj = calculate_VPP_objective(P, gen_data, lambda, gen_buses)
    
    % 发电成本
    gen_cost = calculate_VPP_generation_cost(P, gen_data);
    
    % 拉格朗日项（收入）
    lagrangian_term = 0;
    for i = 1:length(P)
        bus_idx = gen_buses(i);
        if bus_idx <= length(lambda)
            lagrangian_term = lagrangian_term + lambda(bus_idx) * P(i);
        end
    end
    
    % VPP利润最大化（最小化负利润）
    obj = gen_cost - lagrangian_term;
    
end

%% 量子遗传算法主函数
function [best_solution, best_fitness, convergence] = quantum_genetic_algorithm(objective_func, params)
    
    % 参数提取
    pop_size = params.pop_size;
    max_gen = params.max_gen;
    prob_size = params.prob_size;
    bounds = params.bounds;
    
    % 初始化量子种群（概率幅表示）
    Q = initialize_quantum_population(pop_size, prob_size);
    
    % 最佳解记录
    best_fitness = inf;
    best_solution = [];
    fitness_history = zeros(max_gen, 1);
    
    for gen = 1:max_gen
        
        % 1. 量子测量产生经典种群
        P = quantum_measurement(Q, bounds, pop_size);
        
        % 2. 评估适应度
        fitness = zeros(pop_size, 1);
        for i = 1:pop_size
            fitness(i) = objective_func(P(i, :)');
        end
        
        % 3. 更新最佳解
        [min_fitness, min_idx] = min(fitness);
        if min_fitness < best_fitness
            best_fitness = min_fitness;
            best_solution = P(min_idx, :)';
        end
        
        fitness_history(gen) = best_fitness;
        
        % 4. 量子门更新
        Q = quantum_gate_update(Q, P, fitness, best_solution);
        
        % 5. 量子灾变（防止早熟）
        if gen > 10 && std(fitness_history(max(1, gen-10):gen)) < 1e-6
            Q = quantum_catastrophe(Q, 0.1); % 10%的量子灾变概率
        end
    end
    
    convergence = struct();
    convergence.fitness_history = fitness_history;
    convergence.generations = max_gen;
    convergence.final_fitness = best_fitness;
    
end

%% 初始化量子种群
function Q = initialize_quantum_population(pop_size, prob_size)
    
    % 量子比特用概率幅[α, β]表示，满足|α|² + |β|² = 1
    % 初始化为最大叠加态 [1/√2, 1/√2]
    Q = struct();
    Q.alpha = ones(pop_size, prob_size) / sqrt(2);
    Q.beta = ones(pop_size, prob_size) / sqrt(2);
    
end

%% 量子测量
function P = quantum_measurement(Q, bounds, pop_size)
    
    prob_size = size(Q.alpha, 2);
    P = zeros(pop_size, prob_size);
    
    for i = 1:pop_size
        for j = 1:prob_size
            % 基于概率幅进行测量
            if rand() < Q.alpha(i, j)^2
                % 测量结果为0态，映射到下界附近
                P(i, j) = bounds(j, 1) + (bounds(j, 2) - bounds(j, 1)) * rand() * 0.3;
            else
                % 测量结果为1态，映射到上界附近
                P(i, j) = bounds(j, 1) + (bounds(j, 2) - bounds(j, 1)) * (0.7 + rand() * 0.3);
            end
        end
    end
    
end

%% 量子门更新
function Q_new = quantum_gate_update(Q, P, fitness, best_solution)
    
    [pop_size, prob_size] = size(Q.alpha);
    Q_new = Q;
    
    % 找到当前代最佳个体
    [~, best_idx] = min(fitness);
    current_best = P(best_idx, :);
    
    for i = 1:pop_size
        for j = 1:prob_size
            
            % 计算旋转角度
            delta_theta = calculate_rotation_angle(P(i, j), current_best(j), ...
                                                 best_solution(j), fitness(i));
            
            % 量子旋转门
            cos_theta = cos(delta_theta);
            sin_theta = sin(delta_theta);
            
            alpha_new = cos_theta * Q.alpha(i, j) - sin_theta * Q.beta(i, j);
            beta_new = sin_theta * Q.alpha(i, j) + cos_theta * Q.beta(i, j);
            
            Q_new.alpha(i, j) = alpha_new;
            Q_new.beta(i, j) = beta_new;
        end
    end
    
end

%% 计算旋转角度
function theta = calculate_rotation_angle(xi, bi, gi, fi)
    
    % xi: 当前个体的基因值
    % bi: 当前代最佳个体的基因值  
    % gi: 全局最佳个体的基因值
    % fi: 当前个体的适应度
    
    % 自适应旋转角度
    theta_max = 0.05 * pi; % 最大旋转角度
    
    if xi < gi
        theta = theta_max * (1 - exp(-fi/1000));
    elseif xi > gi
        theta = -theta_max * (1 - exp(-fi/1000));
    else
        theta = 0;
    end
    
    % 添加随机性
    theta = theta + (rand() - 0.5) * 0.01 * pi;
    
end

%% 量子灾变
function Q_new = quantum_catastrophe(Q, prob)
    
    Q_new = Q;
    [pop_size, prob_size] = size(Q.alpha);
    
    for i = 1:pop_size
        if rand() < prob
            % 重新初始化为最大叠加态
            Q_new.alpha(i, :) = ones(1, prob_size) / sqrt(2);
            Q_new.beta(i, :) = ones(1, prob_size) / sqrt(2);
        end
    end
    
end