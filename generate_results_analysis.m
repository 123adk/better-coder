%% 生成结果分析和可视化
function generate_results_analysis(scheduling_results, total_costs, lambda_history, VPP_data)
    
    fprintf('生成结果分析图表...\n');
    
    % 提取24小时数据
    hours = 1:24;
    num_VPPs = length(VPP_data);
    
    % 提取各VPP的发电出力
    vpp_generation = zeros(24, num_VPPs);
    convergence_iterations = zeros(24, 1);
    
    for hour = 1:24
        result = scheduling_results{hour};
        convergence_iterations(hour) = result.convergence.iterations;
        
        % 分配发电出力到各VPP
        gen_idx = 1;
        for vpp = 1:num_VPPs
            num_gens = length(VPP_data{vpp}.gen_indices);
            vpp_gen_output = result.gen_output(gen_idx:gen_idx+num_gens-1);
            vpp_generation(hour, vpp) = sum(vpp_gen_output);
            gen_idx = gen_idx + num_gens;
        end
    end
    
    % 创建图形窗口
    figure('Position', [100, 100, 1200, 800]);
    
    %% 子图1：24小时总成本曲线
    subplot(2, 3, 1);
    plot(hours, total_costs, 'b-o', 'LineWidth', 2, 'MarkerSize', 6);
    xlabel('小时');
    ylabel('总成本 ($)');
    title('24小时调度总成本');
    grid on;
    
    % 添加成本统计信息
    avg_cost = mean(total_costs);
    max_cost = max(total_costs);
    min_cost = min(total_costs);
    text(0.02, 0.98, sprintf('平均: $%.0f\n最大: $%.0f\n最小: $%.0f', ...
         avg_cost, max_cost, min_cost), 'Units', 'normalized', ...
         'VerticalAlignment', 'top', 'BackgroundColor', 'white');
    
    %% 子图2：各VPP发电出力堆叠图
    subplot(2, 3, 2);
    area(hours, vpp_generation);
    xlabel('小时');
    ylabel('发电出力 (MW)');
    title('各VPP发电出力分布');
    legend(arrayfun(@(x) sprintf('VPP %d', x), 1:num_VPPs, 'UniformOutput', false), ...
           'Location', 'best');
    grid on;
    
    %% 子图3：平均电价（拉格朗日乘子）
    subplot(2, 3, 3);
    avg_lambda = mean(lambda_history, 2);
    plot(hours, avg_lambda, 'r-s', 'LineWidth', 2, 'MarkerSize', 6);
    xlabel('小时');
    ylabel('平均电价 ($/MWh)');
    title('24小时平均电价变化');
    grid on;
    
    %% 子图4：收敛性分析
    subplot(2, 3, 4);
    bar(hours, convergence_iterations);
    xlabel('小时');
    ylabel('收敛迭代次数');
    title('优化算法收敛性');
    grid on;
    
    % 添加收敛统计
    avg_iter = mean(convergence_iterations);
    max_iter = max(convergence_iterations);
    text(0.02, 0.98, sprintf('平均迭代: %.1f\n最大迭代: %d', avg_iter, max_iter), ...
         'Units', 'normalized', 'VerticalAlignment', 'top', 'BackgroundColor', 'white');
    
    %% 子图5：负荷曲线对比
    subplot(2, 3, 5);
    
    % 标准负荷曲线（来自主函数）
    load_forecast = [0.52, 0.48, 0.46, 0.44, 0.43, 0.45, 0.52, 0.65, ...
                     0.78, 0.85, 0.88, 0.90, 0.92, 0.90, 0.88, 0.87, ...
                     0.89, 0.93, 0.96, 0.95, 0.90, 0.80, 0.70, 0.58];
    
    total_generation_hourly = sum(vpp_generation, 2);
    total_load_base = sum(cell2mat(cellfun(@(x) sum(x.load_data), VPP_data, 'UniformOutput', false)));
    expected_load = total_load_base * load_forecast;
    
    plot(hours, expected_load, 'g-o', 'LineWidth', 2, 'DisplayName', '预期负荷');
    hold on;
    plot(hours, total_generation_hourly, 'b-s', 'LineWidth', 2, 'DisplayName', '总发电');
    xlabel('小时');
    ylabel('功率 (MW)');
    title('发电-负荷平衡');
    legend('show');
    grid on;
    
    %% 子图6：VPP成本分析
    subplot(2, 3, 6);
    
    % 计算各VPP的日总成本
    vpp_daily_costs = zeros(num_VPPs, 1);
    for vpp = 1:num_VPPs
        vpp_hourly_costs = zeros(24, 1);
        for hour = 1:24
            result = scheduling_results{hour};
            gen_idx = 1;
            for v = 1:vpp-1
                gen_idx = gen_idx + length(VPP_data{v}.gen_indices);
            end
            num_gens = length(VPP_data{vpp}.gen_indices);
            vpp_gen_output = result.gen_output(gen_idx:gen_idx+num_gens-1);
            vpp_hourly_costs(hour) = calculate_VPP_generation_cost(vpp_gen_output, VPP_data{vpp}.gen_data);
        end
        vpp_daily_costs(vpp) = sum(vpp_hourly_costs);
    end
    
    pie(vpp_daily_costs, arrayfun(@(x) sprintf('VPP %d\n$%.0f', x, vpp_daily_costs(x)), ...
                                  1:num_VPPs, 'UniformOutput', false));
    title('各VPP日总成本分布');
    
    % 调整布局
    sgtitle('IEEE 118节点VPP协同调度结果分析', 'FontSize', 16, 'FontWeight', 'bold');
    
    % 保存图表
    saveas(gcf, 'IEEE118_VPP_Scheduling_Results.png');
    saveas(gcf, 'IEEE118_VPP_Scheduling_Results.fig');
    
    %% 生成详细报告
    generate_detailed_report(scheduling_results, total_costs, lambda_history, VPP_data, vpp_generation);
    
    fprintf('结果分析完成，图表已保存\n');
    
end

%% 生成详细报告
function generate_detailed_report(scheduling_results, total_costs, lambda_history, VPP_data, vpp_generation)
    
    % 打开文件写入报告
    fid = fopen('IEEE118_VPP_Scheduling_Report.txt', 'w');
    
    fprintf(fid, '=== IEEE 118节点VPP协同调度仿真报告 ===\n\n');
    fprintf(fid, '仿真时间: %s\n\n', datestr(now));
    
    % 系统基本信息
    fprintf(fid, '1. 系统基本信息\n');
    fprintf(fid, '   VPP数量: %d\n', length(VPP_data));
    for vpp = 1:length(VPP_data)
        fprintf(fid, '   VPP %d: 发电机组 %d 台, 负荷节点 %d 个\n', ...
            vpp, length(VPP_data{vpp}.gen_indices), length(VPP_data{vpp}.load_indices));
    end
    fprintf(fid, '\n');
    
    % 优化结果汇总
    fprintf(fid, '2. 优化结果汇总\n');
    fprintf(fid, '   24小时总成本: $%.2f\n', sum(total_costs));
    fprintf(fid, '   平均小时成本: $%.2f\n', mean(total_costs));
    fprintf(fid, '   最高小时成本: $%.2f (第%d小时)\n', max(total_costs), find(total_costs == max(total_costs), 1));
    fprintf(fid, '   最低小时成本: $%.2f (第%d小时)\n', min(total_costs), find(total_costs == min(total_costs), 1));
    fprintf(fid, '\n');
    
    % 电价分析
    avg_lambda = mean(lambda_history, 2);
    fprintf(fid, '3. 电价分析\n');
    fprintf(fid, '   平均电价: %.2f $/MWh\n', mean(avg_lambda));
    fprintf(fid, '   最高电价: %.2f $/MWh (第%d小时)\n', max(avg_lambda), find(avg_lambda == max(avg_lambda), 1));
    fprintf(fid, '   最低电价: %.2f $/MWh (第%d小时)\n', min(avg_lambda), find(avg_lambda == min(avg_lambda), 1));
    fprintf(fid, '\n');
    
    % 各VPP性能
    fprintf(fid, '4. 各VPP发电性能\n');
    for vpp = 1:length(VPP_data)
        daily_gen = sum(vpp_generation(:, vpp));
        avg_hourly_gen = mean(vpp_generation(:, vpp));
        max_hourly_gen = max(vpp_generation(:, vpp));
        fprintf(fid, '   VPP %d: 日总发电 %.1f MWh, 平均 %.1f MW, 峰值 %.1f MW\n', ...
            vpp, daily_gen, avg_hourly_gen, max_hourly_gen);
    end
    fprintf(fid, '\n');
    
    % 收敛性分析
    convergence_iterations = zeros(24, 1);
    converged_hours = 0;
    for hour = 1:24
        convergence_iterations(hour) = scheduling_results{hour}.convergence.iterations;
        if scheduling_results{hour}.convergence.converged
            converged_hours = converged_hours + 1;
        end
    end
    
    fprintf(fid, '5. 算法收敛性\n');
    fprintf(fid, '   完全收敛小时数: %d/24\n', converged_hours);
    fprintf(fid, '   平均迭代次数: %.1f\n', mean(convergence_iterations));
    fprintf(fid, '   最大迭代次数: %d\n', max(convergence_iterations));
    fprintf(fid, '\n');
    
    % 逐小时详细结果
    fprintf(fid, '6. 逐小时详细结果\n');
    fprintf(fid, '小时\t总成本($)\t平均电价($/MWh)\t迭代次数\t收敛状态\n');
    for hour = 1:24
        converged_str = scheduling_results{hour}.convergence.converged ? '是' : '否';
        fprintf(fid, '%d\t%.2f\t%.2f\t%d\t%s\n', ...
            hour, total_costs(hour), avg_lambda(hour), ...
            convergence_iterations(hour), converged_str);
    end
    
    fclose(fid);
    
    fprintf('详细报告已保存到 IEEE118_VPP_Scheduling_Report.txt\n');
    
end