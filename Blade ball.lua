        ballVel=Vector3.new(),
        lastParryTime=0,
        isDoubleTapping=false,
        ui=nil,
        espParts={},
        threatIndicator=nil
    }

    -- ═══════════════ UTILITÁRIOS MATEMÁTICOS ═══════════════
    
    -- Gerador Gaussiano (Box-Muller transform simplificado ou soma de uniformes)
    -- Soma de 12 uniformes [0,1] menos 6 dá uma aproximação razoável de normal(0,1)
    local function gaussianRandom(mean, stdDev)
        local sum = 0
        for _ = 1, 12 do
            sum += math.random()
        end
        return mean + (sum - 6) * stdDev
    end

    local function clamp(val, min, max)
        return val < min and min or (val > max and max or val)
    end

    -- Simula erro de leitura humana: altera ligeiramente a posição/velocidade percebida
    local function applyReadingNoise(pos, vel, noisePercent)
        if noisePercent == 0 then return pos, vel end
        
        local noiseScale = 0.5 -- Fator de escala para não ficar absurdamente errado
        local noiseX = (math.random(-noisePercent, noisePercent) / 100) * noiseScale
        local noiseY = (math.random(-noisePercent, noisePercent) / 100) * noiseScale
        local noiseZ = (math.random(-noisePercent, noisePercent) / 100) * noiseScale
        
        local noisyPos = Vector3.new(pos.X + noiseX, pos.Y + noiseY, pos.Z +
