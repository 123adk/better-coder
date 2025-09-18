%% 改进的拉格朗日对偶优化算法
% 修正收敛问题：
% 1. 改进参数设置，避免结果不变
% 2. 增加自适应步长和随机扰动
% 3. 修正功率平衡计算

function [gen_output, lambda_final, convergence_info] = ...
    lagrangian_dual_optimization_improved(VPP_data, load_demand, lambda_init, hour)
    
    % 参数设置
    max_iter = 100;
    tolerance = 1e-4;
    alpha_init = 0.1;      % 初始步长
    alpha_min = 0.001;     % 最小步长
    alpha_decay = 0.95;    % 步长衰减因子
    
    num_VPPs = length(VPP_data);
    num_buses = length(lambda_init);
    
    % 初始化
    lambda = lambda_init;
    alpha = alpha_init;
    convergence_history = [];
    
    % 存储最佳解
    best_lambda = lambda;
    best_objective = inf;
    
    fprintf('  拉格朗日对偶优化开始...\n');
    
    for iter = 1:max_iter
        
        % 1. 并行求解各VPP子问题
        vpp_solutions = cell(num_VPPs, 1);
        
        if ~isempty(gcp('nocreate'))
            % 并行计算
            parfor vpp = 1:num_VPPs
                vpp_solutions{vpp} = solve_VPP_subproblem_QGA(VPP_data{vpp}, lambda, hour);
            end
        else
            % 串行计算
            for vpp = 1:num_VPPs
                vpp_solutions{vpp} = solve_VPP_subproblem_QGA(VPP_data{vpp}, lambda, hour);
            end
        end
        
        % 2. 计算总发电出力和功率不平衡
        total_generation = zeros(num_buses, 1);
        total_cost = 0;
        
        for vpp = 1:num_VPPs
            sol = vpp_solutions{vpp};
            gen_buses = VPP_data{vpp}.gen_buses;
            
            % 累加各母线的发电出力
            for i = 1:length(gen_buses)
                bus_idx = gen_buses(i);
                if bus_idx <= num_buses
                    total_generation(bus_idx) = total_generation(bus_idx) + sol.gen_output(i);
                end
            end
            
            total_cost = total_cost + sol.cost;
        end
        
        % 功率不平衡量
        power_imbalance = total_generation - load_demand;
        
        % 3. 检查收敛性
        max_imbalance = max(abs(power_imbalance));
        convergence_history(iter) = max_imbalance;
        
        if max_imbalance < tolerance
            fprintf('  第%d次迭代收敛，最大功率不平衡: %.6f MW\n', iter, max_imbalance);
            break;
        end
        
        % 4. 更新拉格朗日乘子（自适应步长）
        lambda_new = lambda - alpha * power_imbalance;
        
        % 确保拉格朗日乘子为正值（电价不能为负）
        lambda_new = max(lambda_new, 1); % 最小电价1$/MWh
        
        % 5. 自适应步长调整
        objective_new = total_cost + lambda_new' * power_imbalance;
        
        if objective_new < best_objective
            best_lambda = lambda_new;
            best_objective = objective_new;
            alpha = min(alpha * 1.05, alpha_init); % 适当增加步长
        else
            alpha = alpha * alpha_decay; % 减小步长
            if alpha < alpha_min
                alpha = alpha_min;
                % 添加随机扰动避免陷入局部最优
                lambda_new = lambda_new + randn(size(lambda_new)) * 0.1;
                lambda_new = max(lambda_new, 1);
            end
        end
        
        lambda = lambda_new;
        
        % 显示进度
        if mod(iter, 10) == 0
            fprintf('  迭代%d: 最大不平衡=%.4f MW, 步长=%.4f, 目标值=%.2f\n', ...
                iter, max_imbalance, alpha, objective_new);
        end
    end
    
    % 最终解
    lambda_final = best_lambda;
    
    % 计算最终的发电出力
    gen_output = [];
    final_solutions = cell(num_VPPs, 1);
    
    if ~isempty(gcp('nocreate'))
        parfor vpp = 1:num_VPPs
            final_solutions{vpp} = solve_VPP_subproblem_QGA(VPP_data{vpp}, lambda_final, hour);
        end
    else
        for vpp = 1:num_VPPs
            final_solutions{vpp} = solve_VPP_subproblem_QGA(VPP_data{vpp}, lambda_final, hour);
        end
    end
    
    % 组织输出
    for vpp = 1:num_VPPs
        gen_output = [gen_output; final_solutions{vpp}.gen_output];
    end
    
    % 收敛信息
    convergence_info = struct();
    convergence_info.iterations = iter;
    convergence_info.final_imbalance = max_imbalance;
    convergence_info.converged = (max_imbalance < tolerance);
    convergence_info.history = convergence_history;
    convergence_info.final_objective = best_objective;
    
    if ~convergence_info.converged
        fprintf('  警告：第%d小时优化未完全收敛，最大不平衡: %.4f MW\n', hour, max_imbalance);
    end

end